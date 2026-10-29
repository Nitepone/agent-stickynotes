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
        fn set_agent_write_enabled(self: &BoardController, enabled: bool);
        #[qinvokable]
        fn claude_setup_command(self: &BoardController) -> QString;
        #[qinvokable]
        fn save_screenshot(self: &BoardController, path: &QString) -> bool;
    }

    impl cxx_qt::Threading for BoardController {}
    impl cxx_qt::Initialize for BoardController {}
}

use std::path::PathBuf;
use std::pin::Pin;

use cxx_qt::Threading;
use cxx_qt_lib::{QString, QUrl};
use stickynotes_core::{Applied, Command, Origin, Result as CoreResult};
use uuid::Uuid;

use crate::context;
use crate::viewmodel::{self, TaskForm};

#[derive(Default)]
pub struct BoardControllerRust {
    board_json: QString,
    window_title: QString,
    dirty: bool,
    has_path: bool,
    agent_write: bool,
    endpoint: QString,
    /// Dev aid: `STICKYNOTES_SCREENSHOT=out.png[:scene]` renders the window
    /// to a PNG and quits (see Main.qml).
    screenshot_request: QString,
}

impl cxx_qt::Initialize for qobject::BoardController {
    fn initialize(mut self: Pin<&mut Self>) {
        let ctx = context::get();
        self.as_mut()
            .set_endpoint(QString::from(ctx.endpoint.as_str()));
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
