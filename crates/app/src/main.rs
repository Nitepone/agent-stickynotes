mod context;
mod controller;
mod drafting;
mod editor;
mod motion;
mod settings;
mod theme;
mod viewmodel;

use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{Context, Result};
use clap::Parser;
use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};
use stickynotes_core::BoardStore;

use crate::context::AppContext;
use crate::drafting::claude_code::ClaudeCodeBackend;
use crate::settings::Config;

/// A local kanban board for humans and AI agents.
#[derive(Parser)]
#[command(version)]
struct Cli {
    /// Board file to open (created if it does not exist).
    file: Option<PathBuf>,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    if std::env::var_os("QT_QUICK_CONTROLS_STYLE").is_none() {
        // SAFETY: no other threads exist yet.
        unsafe { std::env::set_var("QT_QUICK_CONTROLS_STYLE", "Fusion") };
    }

    let config = Config::new()?;
    let settings = config.load_settings();
    let token = config.token()?;
    let claude_command = settings.claude_command.clone();
    let store = BoardStore::new(settings.agent_write);
    open_initial_board(&store, cli.file, settings.last_file.clone());

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()?;
    let server = runtime
        .block_on(stickynotes_server::start(
            store.clone(),
            token.clone(),
            settings.port,
        ))
        .context("starting the agent server")?;
    let endpoint = format!("http://{}", server.addr);
    eprintln!("agent API: {endpoint}/api/v1  MCP: {endpoint}/mcp");

    context::init(AppContext {
        store,
        config,
        settings: settings.into(),
        endpoint,
        token,
        drafter: Arc::new(ClaudeCodeBackend::new(claude_command)),
        system_reduced_motion: motion::system_prefers_reduced_motion(),
        spell: editor::SpellChecker::load(),
    });

    let mut app = QGuiApplication::new();
    controller::qobject::install_activity_filter();
    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/StickyNotes/qml/Main.qml"));
    }
    let code = app.as_mut().map_or(1, |app| app.exec());

    server.shutdown();
    drop(engine);
    drop(app);
    runtime.shutdown_timeout(std::time::Duration::from_secs(1));
    std::process::exit(code);
}

/// Open the file from the command line, else the last file used, else start
/// with a new board.
fn open_initial_board(store: &BoardStore, cli_file: Option<PathBuf>, last: Option<PathBuf>) {
    if let Some(path) = cli_file {
        let result = if path.exists() {
            store.open(&path)
        } else {
            store.save_as(&path)
        };
        if let Err(e) = result {
            eprintln!("error: {e}");
        }
    } else if let Some(path) = last.filter(|p| p.exists())
        && let Err(e) = store.open(&path)
    {
        eprintln!("warning: could not reopen {}: {e}", path.display());
    }
}
