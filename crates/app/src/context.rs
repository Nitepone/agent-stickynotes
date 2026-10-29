//! Process-wide state shared by the QML controller. Set once in `main`
//! before the QML engine is created.

use std::sync::{Arc, Mutex, OnceLock};

use stickynotes_core::BoardStore;

use crate::settings::{Config, Settings};

pub struct AppContext {
    pub store: Arc<BoardStore>,
    pub config: Config,
    pub settings: Mutex<Settings>,
    /// Base URL of the agent server, e.g. `http://127.0.0.1:7317`.
    pub endpoint: String,
    pub token: String,
}

impl AppContext {
    /// Update settings in memory and on disk.
    pub fn update_settings(&self, f: impl FnOnce(&mut Settings)) {
        let mut settings = self.settings.lock().unwrap();
        f(&mut settings);
        if let Err(e) = self.config.save_settings(&settings) {
            eprintln!("warning: could not save settings: {e:#}");
        }
    }

    pub fn claude_setup_command(&self) -> String {
        format!(
            "claude mcp add --transport http --scope user stickynotes {}/mcp --header \"Authorization: Bearer {}\"",
            self.endpoint, self.token
        )
    }
}

static CONTEXT: OnceLock<AppContext> = OnceLock::new();

pub fn init(ctx: AppContext) {
    if CONTEXT.set(ctx).is_err() {
        panic!("app context initialized twice");
    }
}

pub fn get() -> &'static AppContext {
    CONTEXT.get().expect("app context not initialized")
}
