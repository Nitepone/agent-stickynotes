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
        #[qproperty(bool, reduce_motion)]
        #[qproperty(QString, motion_setting)]
        #[qproperty(i64, last_interaction_ms)]
        #[qproperty(QString, theme_mode)]
        #[qproperty(QString, primary_color)]
        #[qproperty(QString, secondary_color)]
        #[qproperty(bool, generating)]
        #[qproperty(QString, generator_name)]
        #[qproperty(QString, screenshot_request)]
        type BoardController = super::BoardControllerRust;

        #[qinvokable]
        fn new_board(self: Pin<&mut BoardController>);
        #[qinvokable]
        fn open_file(self: Pin<&mut BoardController>, url: &QUrl) -> QString;
        #[qinvokable]
        fn save(self: Pin<&mut BoardController>, force: bool) -> QString;
        #[qinvokable]
        fn save_as(self: Pin<&mut BoardController>, url: &QUrl) -> QString;
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

        /// "system", "on" or "off". Returns false for anything else.
        #[qinvokable]
        fn choose_motion_setting(self: Pin<&mut BoardController>, setting: &QString) -> bool;
        /// Remember when the user last used the app (ms since the epoch).
        #[qinvokable]
        fn record_interaction(self: Pin<&mut BoardController>, ms: i64);

        /// Theme choices. They apply immediately and are saved. These return false if the value is not valid and was ignored.
        #[qinvokable]
        fn choose_theme_mode(self: Pin<&mut BoardController>, mode: &QString) -> bool;
        #[qinvokable]
        fn choose_primary_color(self: Pin<&mut BoardController>, color: &QString) -> bool;
        #[qinvokable]
        fn choose_secondary_color(self: Pin<&mut BoardController>, color: &QString) -> bool;
        /// Back to the theme's default primary and secondary colors.
        #[qinvokable]
        fn reset_theme_colors(self: Pin<&mut BoardController>);
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
use stickynotes_core::{Applied, Command, Origin, Result as CoreResult};
use uuid::Uuid;

use crate::context;
use crate::drafting::CancelToken;
use crate::viewmodel::{self, TaskForm};
use crate::{motion, theme};

#[derive(Default)]
pub struct BoardControllerRust {
    board_json: QString,
    window_title: QString,
    dirty: bool,
    has_path: bool,
    agent_write: bool,
    endpoint: QString,
    reduce_motion: bool,
    motion_setting: QString,
    last_interaction_ms: i64,
    theme_mode: QString,
    primary_color: QString,
    secondary_color: QString,
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
            .set_generator_name(QString::from(ctx.drafter.name()));
        {
            let settings = ctx.settings.lock().unwrap().clone();
            let motion = motion::normalize_setting(&settings.reduce_motion);
            self.as_mut().set_motion_setting(QString::from(motion));
            self.as_mut()
                .set_reduce_motion(motion::effective(motion, ctx.system_reduced_motion));
            self.as_mut()
                .set_last_interaction_ms(settings.last_interaction_ms);
            self.as_mut()
                .set_theme_mode(QString::from(theme::normalize_mode(&settings.theme_mode)));
            // Stored colors that are no longer valid fall back to the default.
            let color = |c: &str| theme::normalize_color(c).unwrap_or_default();
            self.as_mut()
                .set_primary_color(QString::from(color(&settings.primary_color).as_str()));
            self.as_mut()
                .set_secondary_color(QString::from(color(&settings.secondary_color).as_str()));
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

    fn new_board(self: Pin<&mut Self>) {
        context::get().store.new_board();
    }

    fn open_file(self: Pin<&mut Self>, url: &QUrl) -> QString {
        file_op(url, |path| {
            context::get().store.open(&path)?;
            remember_file(path);
            Ok(())
        })
    }

    fn save(self: Pin<&mut Self>, force: bool) -> QString {
        let result = context::get().store.save(force);
        to_qstring(viewmodel::result_json(result.map(|_| None)))
    }

    fn save_as(self: Pin<&mut Self>, url: &QUrl) -> QString {
        file_op(url, |path| {
            context::get().store.save_as(&path)?;
            remember_file(path);
            Ok(())
        })
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
        to_qstring(
            context::get()
                .store
                .read(|board, _| viewmodel::project_json(board)),
        )
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

    fn choose_theme_mode(mut self: Pin<&mut Self>, mode: &QString) -> bool {
        let text = String::from(mode);
        let mode = theme::normalize_mode(&text);
        // Only "light" and "dark" are modes; unknown text is not silently "light".
        if !text.trim().eq_ignore_ascii_case(mode) {
            return false;
        }
        self.as_mut().set_theme_mode(QString::from(mode));
        context::get().update_settings(|s| s.theme_mode = mode.into());
        true
    }

    fn choose_primary_color(mut self: Pin<&mut Self>, color: &QString) -> bool {
        let Some(color) = theme::normalize_color(&String::from(color)) else {
            return false;
        };
        self.as_mut()
            .set_primary_color(QString::from(color.as_str()));
        context::get().update_settings(|s| s.primary_color = color);
        true
    }

    fn choose_secondary_color(mut self: Pin<&mut Self>, color: &QString) -> bool {
        let Some(color) = theme::normalize_color(&String::from(color)) else {
            return false;
        };
        self.as_mut()
            .set_secondary_color(QString::from(color.as_str()));
        context::get().update_settings(|s| s.secondary_color = color);
        true
    }

    fn choose_motion_setting(mut self: Pin<&mut Self>, setting: &QString) -> bool {
        let text = String::from(setting);
        let setting = motion::normalize_setting(&text);
        if !text.trim().eq_ignore_ascii_case(setting) {
            return false;
        }
        let ctx = context::get();
        self.as_mut().set_motion_setting(QString::from(setting));
        self.as_mut()
            .set_reduce_motion(motion::effective(setting, ctx.system_reduced_motion));
        ctx.update_settings(|s| s.reduce_motion = setting.into());
        true
    }

    fn record_interaction(mut self: Pin<&mut Self>, ms: i64) {
        // Only ever moves forward, so a late or repeated call cannot make
        // notes the user already saw glow again.
        if ms > *self.last_interaction_ms() {
            self.as_mut().set_last_interaction_ms(ms);
            context::get().update_settings(|s| s.last_interaction_ms = ms);
        }
    }

    fn reset_theme_colors(mut self: Pin<&mut Self>) {
        self.as_mut().set_primary_color(QString::default());
        self.as_mut().set_secondary_color(QString::default());
        context::get().update_settings(|s| {
            s.primary_color.clear();
            s.secondary_color.clear();
        });
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
            let (document_prompt, code_guidance) = ctx.store.read(|board, _| {
                (
                    board.project.document_prompt.clone(),
                    board.project.code_guidance.clone(),
                )
            });
            form.draft_request(&document_prompt, &code_guidance)
        });
        let request = match request {
            Ok(request) => request,
            Err(message) => return self.finish_generation(viewmodel::error_json(&message)),
        };

        let token = CancelToken::new();
        self.as_mut().rust_mut().generation = Some(token.clone());
        self.as_mut().set_generating(true);

        let backend = ctx.drafter.clone();
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

fn remember_file(path: PathBuf) {
    context::get().update_settings(|s| s.last_file = Some(path));
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
