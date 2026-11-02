//! `BoardController`: the QML-facing controller. It turns user intents from
//! the views into core commands and republishes store state as properties.
//! It never mutates the board itself; the store notifies it of every change
//! (including agent edits) and it refreshes its properties on the Qt thread.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qurl.h");
        type QUrl = cxx_qt_lib::QUrl;
        include!("stickynotes/cpp/screenshot.h");
        fn save_window_screenshot(path: &QString) -> bool;
        include!("stickynotes/cpp/activity.h");
        fn install_activity_filter();
        fn last_activity_ms() -> i64;
        fn simulate_user_activity();
        fn simulate_synthetic_activity();
        include!("stickynotes/cpp/window_icon.h");
        fn add_window_icon(png: &[u8]);
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, board_json)]
        #[qproperty(QString, window_title)]
        #[qproperty(bool, dirty)]
        #[qproperty(bool, has_path)]
        #[qproperty(bool, agent_write)]
        #[qproperty(QString, endpoint)]
        #[qproperty(i64, last_interaction_ms)]
        #[qproperty(QString, prefs_json)]
        #[qproperty(bool, spell_available)]
        #[qproperty(QString, app_version)]
        #[qproperty(bool, generating)]
        #[qproperty(QString, generator_name)]
        #[qproperty(QString, screenshot_request)]
        type BoardController = super::BoardControllerRust;

        #[qinvokable]
        fn projects_json(self: &BoardController) -> QString;
        #[qinvokable]
        fn new_project(self: Pin<&mut BoardController>, name: &QString) -> QString;
        #[qinvokable]
        fn open_project(self: Pin<&mut BoardController>, dir: &QString) -> QString;
        #[qinvokable]
        fn open_project_folder(self: Pin<&mut BoardController>, url: &QUrl) -> QString;
        #[qinvokable]
        fn save(self: Pin<&mut BoardController>, force: bool) -> QString;
        #[qinvokable]
        fn export_markdown(self: &BoardController, url: &QUrl) -> QString;

        #[qinvokable]
        fn task_json(self: &BoardController, id: &QString) -> QString;
        #[qinvokable]
        fn relation_options(self: &BoardController) -> QString;
        #[qinvokable]
        fn create_task(self: &BoardController, column_id: &QString, form: &QString) -> QString;
        #[qinvokable]
        fn update_task(self: &BoardController, id: &QString, form: &QString) -> QString;
        #[qinvokable]
        fn move_task(
            self: &BoardController,
            id: &QString,
            column_id: &QString,
            position: i32,
        ) -> QString;
        #[qinvokable]
        fn delete_task(self: &BoardController, id: &QString) -> QString;

        #[qinvokable]
        fn create_column(
            self: &BoardController,
            position: i32,
            title: &QString,
            description: &QString,
        ) -> QString;
        #[qinvokable]
        fn update_column(
            self: &BoardController,
            id: &QString,
            title: &QString,
            description: &QString,
        ) -> QString;
        #[qinvokable]
        fn move_column(self: &BoardController, id: &QString, position: i32) -> QString;
        #[qinvokable]
        fn delete_column(self: &BoardController, id: &QString, force: bool) -> QString;
        #[qinvokable]
        fn rename_board(self: &BoardController, title: &QString) -> QString;
        #[qinvokable]
        fn project_json(self: &BoardController) -> QString;
        /// Every file in the project's `artifacts/` folder, newest first.
        #[qinvokable]
        fn artifacts_json(self: &BoardController) -> QString;
        #[qinvokable]
        fn artifact_json(self: &BoardController, name: &QString) -> QString;
        #[qinvokable]
        fn update_project(
            self: &BoardController,
            document_prompt: &QString,
            code_guidance: &QString,
        ) -> QString;
        #[qinvokable]
        fn export_skill(self: &BoardController, url: &QUrl) -> QString;

        #[qinvokable]
        fn set_agent_write_enabled(self: &BoardController, enabled: bool);
        #[qinvokable]
        fn claude_setup_command(self: &BoardController) -> QString;

        /// Remember when the user last used the app (ms since the epoch).
        #[qinvokable]
        fn record_interaction(self: Pin<&mut BoardController>, ms: i64);

        /// Change one preference (keys: see `settings::PREFS`), save it and
        /// republish `prefsJson`. The empty text resets a color. Returns
        /// false and changes nothing if the key or value is not valid.
        #[qinvokable]
        fn choose_pref(self: Pin<&mut BoardController>, key: &QString, value: &QString) -> bool;
        /// Misspelled words in `text`, as JSON `[[start, length], ...]` in
        /// UTF-16 units. Empty while spell check is off.
        #[qinvokable]
        fn misspelled_ranges(self: &BoardController, text: &QString) -> QString;

        #[qinvokable]
        fn save_screenshot(self: &BoardController, path: &QString) -> bool;

        /// When the user last gave the app input (ms since the epoch; 0 if
        /// never). Polled by the window to drive the glow of changed notes.
        #[qinvokable]
        fn last_input_ms(self: &BoardController) -> i64;
        /// Dev aid: deliver a mouse move as the system would.
        #[qinvokable]
        fn simulate_activity(self: &BoardController, counted: bool);

        /// Draft requirements and criteria for the task form (JSON) in the
        /// background; the outcome arrives through `generation_finished`.
        #[qinvokable]
        fn start_generation(self: Pin<&mut BoardController>, form: &QString);
        #[qinvokable]
        fn cancel_generation(self: &BoardController);

        /// JSON: `{ok: true, requirements, criteria}` or `{ok: false, code, message}`.
        #[qsignal]
        fn generation_finished(self: Pin<&mut BoardController>, result: QString);
    }

    impl cxx_qt::Threading for BoardController {}
    impl cxx_qt::Initialize for BoardController {}
}

use std::path::PathBuf;
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QString, QUrl};
use stickynotes_core::{Applied, Command, Origin, Result as CoreResult, project};
use uuid::Uuid;

use crate::context;
use crate::drafting::{CancelToken, DraftOptions};
use crate::settings;
use crate::viewmodel::{self, TaskForm};

#[derive(Default)]
pub struct BoardControllerRust {
    board_json: QString,
    window_title: QString,
    dirty: bool,
    has_path: bool,
    agent_write: bool,
    endpoint: QString,
    last_interaction_ms: i64,
    /// The preferences as JSON (see `Settings::prefs_json`).
    prefs_json: QString,
    spell_available: bool,
    /// The Cargo package version, shown in Preferences > About.
    app_version: QString,
    generating: bool,
    generator_name: QString,
    /// Set while a generation runs, so it can be cancelled.
    generation: Option<CancelToken>,
    /// Dev aid: `STICKYNOTES_SCREENSHOT=out.png[:scene]` renders the window
    /// to a PNG and quits (see Main.qml).
    screenshot_request: QString,
}

impl cxx_qt::Initialize for qobject::BoardController {
    fn initialize(mut self: Pin<&mut Self>) {
        let ctx = context::get();
        self.as_mut()
            .set_endpoint(QString::from(ctx.endpoint.as_str()));
        self.as_mut()
            .set_app_version(QString::from(env!("CARGO_PKG_VERSION")));
        {
            let settings = stickynotes_core::store::relock(&ctx.settings).clone();
            self.as_mut().publish_prefs();
            self.as_mut()
                .set_last_interaction_ms(settings.last_interaction_ms);
            self.as_mut().set_spell_available(ctx.spell.available());
        }
        if let Ok(request) = std::env::var("STICKYNOTES_SCREENSHOT") {
            self.as_mut()
                .set_screenshot_request(QString::from(request.as_str()));
        }
        self.as_mut().refresh();

        let thread = self.qt_thread();
        ctx.store.subscribe(move |_change| {
            // Fails only once the controller is destroyed; nothing to do then.
            let _ = thread.queue(|obj| obj.refresh());
        });
    }
}

impl qobject::BoardController {
    /// Republish the preferences, so QML bindings on `prefsJson` update.
    fn publish_prefs(mut self: Pin<&mut Self>) {
        let ctx = context::get();
        let (json, generator) = {
            let settings = stickynotes_core::store::relock(&ctx.settings);
            (
                settings.prefs_json(ctx.system_reduced_motion),
                crate::drafting::select::select(&settings, &ctx.drafter)
                    .name()
                    .to_string(),
            )
        };
        self.as_mut()
            .set_generator_name(QString::from(generator.as_str()));
        self.set_prefs_json(to_qstring(json));
    }

    /// Republish the store's state as properties.
    fn refresh(mut self: Pin<&mut Self>) {
        let snapshot = context::get().store.snapshot();
        let board_json = QString::from(viewmodel::board_json(&snapshot.board).as_str());
        if *self.board_json() != board_json {
            self.as_mut().set_board_json(board_json);
        }
        self.as_mut()
            .set_window_title(QString::from(viewmodel::window_title(&snapshot).as_str()));
        self.as_mut().set_dirty(snapshot.dirty);
        self.as_mut().set_has_path(snapshot.path.is_some());
        self.as_mut().set_agent_write(snapshot.agent_write);
    }

    fn projects_json(&self) -> QString {
        let ctx = context::get();
        let current = ctx.store.project_dir();
        to_qstring(viewmodel::projects_json(
            ctx.config.projects_dir(),
            current.as_deref(),
        ))
    }

    fn new_project(self: Pin<&mut Self>, name: &QString) -> QString {
        let ctx = context::get();
        let name = String::from(name).trim().to_string();
        if name.is_empty() {
            return to_qstring(viewmodel::error_json("give the project a name"));
        }
        let dir = project::new_project_dir(ctx.config.projects_dir(), &name);
        let result = ctx.store.create_project(&dir, &name).map(|_| {
            remember_project(dir);
        });
        to_qstring(viewmodel::result_json(result.map(|_| None::<Applied>)))
    }

    fn open_project(self: Pin<&mut Self>, dir: &QString) -> QString {
        let dir = PathBuf::from(String::from(dir));
        let result = context::get().store.open_project(&dir).map(|_| {
            remember_project(dir);
        });
        to_qstring(viewmodel::result_json(result.map(|_| None::<Applied>)))
    }

    /// A folder picked by hand: a project is opened, an empty folder becomes one.
    fn open_project_folder(self: Pin<&mut Self>, url: &QUrl) -> QString {
        let Some(dir) = url.to_local_file().map(|p| PathBuf::from(String::from(&p))) else {
            return to_qstring(viewmodel::error_json("only local folders are supported"));
        };
        let result = context::get().store.open_or_create_project(&dir).map(|_| {
            remember_project(dir);
        });
        to_qstring(viewmodel::result_json(result.map(|_| None::<Applied>)))
    }

    fn save(self: Pin<&mut Self>, force: bool) -> QString {
        let result = context::get().store.save(force);
        to_qstring(viewmodel::result_json(result.map(|_| None)))
    }

    fn export_markdown(&self, url: &QUrl) -> QString {
        file_op(url, |path| context::get().store.export_markdown(&path))
    }

    fn task_json(&self, id: &QString) -> QString {
        let Some(id) = parse_id(id) else {
            return QString::default();
        };
        let json = context::get()
            .store
            .read(|board, _| viewmodel::task_json(board, id));
        to_qstring(json)
    }

    fn relation_options(&self) -> QString {
        to_qstring(viewmodel::relation_options_json())
    }

    fn create_task(&self, column_id: &QString, form: &QString) -> QString {
        let form = match TaskForm::parse(&String::from(form)) {
            Ok(f) => f,
            Err(e) => return to_qstring(viewmodel::error_json(&e)),
        };
        with_id(column_id, |column| Command::CreateTask {
            column: Some(column),
            position: None,
            draft: form.into_draft(),
        })
    }

    fn update_task(&self, id: &QString, form: &QString) -> QString {
        let form = match TaskForm::parse(&String::from(form)) {
            Ok(f) => f,
            Err(e) => return to_qstring(viewmodel::error_json(&e)),
        };
        with_id(id, |id| Command::UpdateTask {
            id,
            patch: form.into_patch(),
        })
    }

    fn move_task(&self, id: &QString, column_id: &QString, position: i32) -> QString {
        let Some(to_column) = parse_id(column_id) else {
            return bad_id();
        };
        with_id(id, |id| Command::MoveTask {
            id,
            to_column,
            position: usize::try_from(position).ok(),
        })
    }

    fn delete_task(&self, id: &QString) -> QString {
        with_id(id, |id| Command::DeleteTask { id })
    }

    fn create_column(&self, position: i32, title: &QString, description: &QString) -> QString {
        apply(Command::CreateColumn {
            position: usize::try_from(position).ok(),
            title: title.into(),
            description: description.into(),
        })
    }

    fn update_column(&self, id: &QString, title: &QString, description: &QString) -> QString {
        with_id(id, |id| Command::UpdateColumn {
            id,
            title: Some(title.into()),
            description: Some(description.into()),
        })
    }

    fn move_column(&self, id: &QString, position: i32) -> QString {
        with_id(id, |id| Command::MoveColumn {
            id,
            position: usize::try_from(position).unwrap_or(0),
        })
    }

    fn delete_column(&self, id: &QString, force: bool) -> QString {
        with_id(id, |id| Command::DeleteColumn { id, force })
    }

    fn rename_board(&self, title: &QString) -> QString {
        apply(Command::RenameBoard {
            title: title.into(),
        })
    }

    fn project_json(&self) -> QString {
        let store = &context::get().store;
        // Listed first: the store is locked while `read` runs.
        let files = store.artifact_files();
        to_qstring(store.read(|board, _| viewmodel::project_json(board, &files)))
    }

    fn artifacts_json(&self) -> QString {
        to_qstring(viewmodel::artifacts_json(
            &context::get().store.artifact_files(),
        ))
    }

    fn artifact_json(&self, name: &QString) -> QString {
        to_qstring(viewmodel::artifact_json(
            &context::get().store,
            &String::from(name),
        ))
    }

    fn update_project(&self, document_prompt: &QString, code_guidance: &QString) -> QString {
        apply(Command::UpdateProject {
            document_prompt: Some(document_prompt.into()),
            code_guidance: Some(code_guidance.into()),
        })
    }

    fn export_skill(&self, url: &QUrl) -> QString {
        file_op(url, |path| context::get().store.export_skill(&path))
    }

    fn choose_pref(mut self: Pin<&mut Self>, key: &QString, value: &QString) -> bool {
        let Some(pref) = settings::pref(&String::from(key)) else {
            return false;
        };
        let Some(value) = (pref.validate)(&String::from(value)) else {
            return false;
        };
        context::get().update_settings(|s| (pref.set)(s, value));
        self.as_mut().publish_prefs();
        true
    }

    fn misspelled_ranges(&self, text: &QString) -> QString {
        if !stickynotes_core::store::relock(&context::get().settings).spell_check {
            return QString::from("[]");
        }
        let ranges = context::get().spell.misspelled(&String::from(text));
        to_qstring(serde_json::to_string(&ranges).expect("ranges serialize"))
    }

    fn record_interaction(mut self: Pin<&mut Self>, ms: i64) {
        // Only ever moves forward, so a late or repeated call cannot make
        // notes the user already saw glow again.
        if ms > *self.last_interaction_ms() {
            self.as_mut().set_last_interaction_ms(ms);
            context::get().update_settings(|s| s.last_interaction_ms = ms);
        }
    }

    fn set_agent_write_enabled(&self, enabled: bool) {
        let ctx = context::get();
        ctx.store.set_agent_write(enabled);
        ctx.update_settings(|s| s.agent_write = enabled);
    }

    fn claude_setup_command(&self) -> QString {
        to_qstring(context::get().claude_setup_command())
    }

    fn save_screenshot(&self, path: &QString) -> bool {
        qobject::save_window_screenshot(path)
    }

    fn last_input_ms(&self) -> i64 {
        qobject::last_activity_ms()
    }

    fn simulate_activity(&self, counted: bool) {
        if counted {
            qobject::simulate_user_activity();
        } else {
            qobject::simulate_synthetic_activity();
        }
    }

    fn start_generation(mut self: Pin<&mut Self>, form: &QString) {
        // A run in progress keeps its state; only report the refusal.
        if *self.generating() {
            let busy = viewmodel::error_json("A draft is already being generated.");
            return self.generation_finished(to_qstring(busy));
        }
        let ctx = context::get();
        let request = TaskForm::parse(&String::from(form)).and_then(|form| {
            let (document_prompt, code_guidance, categories) = ctx.store.read(|board, _| {
                (
                    board.project.document_prompt.clone(),
                    board.project.code_guidance.clone(),
                    viewmodel::category_infos(board),
                )
            });
            let settings = stickynotes_core::store::relock(&ctx.settings);
            let options = DraftOptions {
                system_prompt: settings.draft_system_prompt.trim().to_string(),
                model: crate::drafting::select::model_for(&settings),
                effort: settings.draft_effort.clone(),
            };
            form.draft_request(&document_prompt, &code_guidance, categories, options)
        });
        let request = match request {
            Ok(request) => request,
            Err(message) => return self.finish_generation(viewmodel::error_json(&message)),
        };

        let token = CancelToken::new();
        self.as_mut().rust_mut().generation = Some(token.clone());
        self.as_mut().set_generating(true);

        let backend = {
            let settings = stickynotes_core::store::relock(&ctx.settings);
            crate::drafting::select::select(&settings, &ctx.drafter)
        };
        let thread = self.qt_thread();
        std::thread::spawn(move || {
            let result = backend.generate(&request, &token);
            let json = viewmodel::draft_result_json(result, &request, backend.name());
            // Fails only if the controller was destroyed; nothing to report to then.
            let _ = thread.queue(move |obj| obj.finish_generation(json));
        });
    }

    fn cancel_generation(&self) {
        if let Some(token) = &self.generation {
            token.cancel();
        }
    }

    /// Back on the Qt thread: record that the run is over and tell the view.
    fn finish_generation(mut self: Pin<&mut Self>, result_json: String) {
        self.as_mut().rust_mut().generation = None;
        self.as_mut().set_generating(false);
        self.generation_finished(to_qstring(result_json));
    }
}

fn apply(cmd: Command) -> QString {
    let result = context::get()
        .store
        .apply(Origin::User, cmd, None)
        .map(|(applied, _)| Some(applied));
    to_qstring(viewmodel::result_json(result))
}

fn with_id(id: &QString, cmd: impl FnOnce(Uuid) -> Command) -> QString {
    match parse_id(id) {
        Some(id) => apply(cmd(id)),
        None => bad_id(),
    }
}

fn file_op(url: &QUrl, op: impl FnOnce(PathBuf) -> CoreResult<()>) -> QString {
    let Some(path) = url.to_local_file().map(|p| PathBuf::from(String::from(&p))) else {
        return to_qstring(viewmodel::error_json("only local files are supported"));
    };
    to_qstring(viewmodel::result_json(op(path).map(|_| None::<Applied>)))
}

fn remember_project(dir: PathBuf) {
    context::get().update_settings(|s| s.last_project = Some(dir));
}

fn parse_id(id: &QString) -> Option<Uuid> {
    Uuid::parse_str(&String::from(id)).ok()
}

fn bad_id() -> QString {
    to_qstring(viewmodel::error_json("invalid id"))
}

fn to_qstring(s: String) -> QString {
    QString::from(s.as_str())
}
