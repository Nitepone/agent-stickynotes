//! The single source of truth shared by the UI and the agent API.
//!
//! `BoardStore` owns the open board plus session state (file path, dirty
//! flag, revision, agent write access). Every mutation goes through
//! [`BoardStore::apply`]; listeners are notified after each change.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use crate::command::{Applied, Command, Origin};
use crate::error::{Error, Result};
use crate::history::History;
use crate::model::{Artifact, ArtifactId, Board, TaskId};
use crate::ops;
use crate::persist::{self, FileStamp};
use crate::project;
use crate::{activity, agent_guide, artifact, backup, export_md};
use chrono::{DateTime, Local};

/// Emitted after any change to the board or session state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Change {
    pub revision: u64,
    pub origin: Origin,
}

/// A consistent copy of the store's state.
#[derive(Debug, Clone)]
pub struct Snapshot {
    pub board: Board,
    pub revision: u64,
    pub dirty: bool,
    pub path: Option<PathBuf>,
    pub agent_write: bool,
}

/// A file in `artifacts/` and where it is attached.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtifactFile {
    pub file: artifact::StoredFile,
    /// `(task id, task number, artifact id)` for each task it is attached to.
    pub tasks: Vec<(TaskId, u64, ArtifactId)>,
    /// When it was added (ms since the epoch): the earliest time a task
    /// recorded it, or the file's modification time if none did.
    pub at_ms: i64,
}

type Listener = Box<dyn Fn(Change) + Send + Sync>;

struct State {
    board: Board,
    path: Option<PathBuf>,
    stamp: Option<FileStamp>,
    dirty: bool,
    revision: u64,
    agent_write: bool,
    history: History,
    /// When the last rolling snapshot was taken; `None` until the first save
    /// after a project is opened.
    last_snapshot: Option<DateTime<Local>>,
    /// A backup problem not yet shown to the user, and whether one was
    /// already reported since the project was opened.
    backup_notice: Option<String>,
    backup_warned: bool,
    clock: Clock,
}

type Clock = Box<dyn Fn() -> DateTime<Local> + Send + Sync>;

impl State {
    /// Back up the file at `path`, then write the board there. A failed
    /// backup never fails the save: it is kept as a one-time notice.
    fn save_to(&mut self, path: &Path) -> Result<Option<FileStamp>> {
        let now = (self.clock)();
        if let Err(e) = backup::before_save(path, now, &mut self.last_snapshot)
            && !self.backup_warned
        {
            self.backup_warned = true;
            self.backup_notice = Some(format!(
                "The board was saved, but its backup could not be made: {e}"
            ));
        }
        persist::save(path, &self.board)
    }

    fn reset_backups(&mut self) {
        self.last_snapshot = None;
        self.backup_warned = false;
        self.backup_notice = None;
    }
}

pub struct BoardStore {
    state: Mutex<State>,
    listeners: Mutex<Vec<Listener>>,
}

impl BoardStore {
    pub fn new(agent_write: bool) -> Arc<Self> {
        Arc::new(BoardStore {
            state: Mutex::new(State {
                board: Board::new_default(),
                path: None,
                stamp: None,
                dirty: false,
                revision: 1,
                agent_write,
                history: History::default(),
                last_snapshot: None,
                backup_notice: None,
                backup_warned: false,
                clock: Box::new(Local::now),
            }),
            listeners: Mutex::new(Vec::new()),
        })
    }

    /// Register a callback run (on the mutating thread) after every change.
    pub fn subscribe(&self, listener: impl Fn(Change) + Send + Sync + 'static) {
        relock(&self.listeners).push(Box::new(listener));
    }

    pub fn snapshot(&self) -> Snapshot {
        let s = self.lock();
        Snapshot {
            board: s.board.clone(),
            revision: s.revision,
            dirty: s.dirty,
            path: s.path.clone(),
            agent_write: s.agent_write,
        }
    }

    /// Run `f` against the current board without cloning it. The store is
    /// locked while `f` runs, so `f` must not call back into the store.
    pub fn read<R>(&self, f: impl FnOnce(&Board, u64) -> R) -> R {
        let s = self.lock();
        f(&s.board, s.revision)
    }

    pub fn revision(&self) -> u64 {
        self.lock().revision
    }

    pub fn agent_write(&self) -> bool {
        self.lock().agent_write
    }

    pub fn set_agent_write(&self, enabled: bool) {
        self.mutate(Origin::User, |s| {
            s.agent_write = enabled;
            Ok(())
        })
        .expect("infallible");
    }

    /// Apply a command. If `expected_revision` is given and the board has
    /// changed since, nothing is applied and `RevisionConflict` is returned.
    pub fn apply(
        &self,
        origin: Origin,
        cmd: Command,
        expected_revision: Option<u64>,
    ) -> Result<(Applied, u64)> {
        self.apply_as(origin, None, cmd, expected_revision)
    }

    /// Like [`apply`](Self::apply), naming the agent (the MCP client) that
    /// issued the command for the activity log (`activity.jsonl`).
    pub fn apply_as(
        &self,
        origin: Origin,
        agent: Option<&str>,
        cmd: Command,
        expected_revision: Option<u64>,
    ) -> Result<(Applied, u64)> {
        self.mutate(origin, |s| {
            if origin == Origin::Agent && !s.agent_write {
                return Err(Error::AgentWriteDisabled);
            }
            if let Some(expected) = expected_revision
                && expected != s.revision
            {
                return Err(Error::RevisionConflict {
                    expected,
                    actual: s.revision,
                });
            }
            // Only the user's own changes can be undone.
            let before = (origin == Origin::User && !matches!(cmd, Command::Restore(_)))
                .then(|| (s.board.clone(), cmd.clone()));
            let log_before =
                (origin == Origin::Agent).then(|| activity::Before::capture(&s.board, &cmd));
            let log_cmd = (origin == Origin::Agent).then(|| cmd.clone());
            let applied = ops::execute(&mut s.board, origin, cmd)?;
            if let (Some(b), Some(c), Some(dir)) = (
                log_before,
                log_cmd,
                s.path.as_deref().and_then(Path::parent),
            ) && let Some(entry) = activity::entry_for(
                origin,
                agent,
                &b,
                &c,
                &applied,
                &s.board,
                chrono::Utc::now(),
            ) {
                // Best effort: the log must never fail a board change.
                let _ = activity::append(dir, &entry);
            }
            if let Some((before, cmd)) = before {
                s.history.record(&cmd, &applied, &before, &s.board);
            }
            s.dirty = true;
            Ok((applied, s.revision + 1))
        })
    }

    /// What Undo and Redo would do, named for a menu ("move #12 to Review").
    pub fn history_labels(&self) -> (Option<String>, Option<String>) {
        self.lock().history.labels()
    }

    /// Undo the user's latest change. Refuses (leaving the history alone) if
    /// what it touched has changed since. Returns the undone change's label.
    pub fn undo(&self) -> Result<String> {
        self.mutate(Origin::User, |s| {
            let (label, snap) = s.history.plan_undo(&s.board)?;
            ops::execute(&mut s.board, Origin::User, Command::Restore(Box::new(snap)))?;
            s.history.finish_undo();
            s.dirty = true;
            Ok(label)
        })
    }

    /// Redo the change last undone, under the same check as [`Self::undo`].
    pub fn redo(&self) -> Result<String> {
        self.mutate(Origin::User, |s| {
            let (label, snap) = s.history.plan_redo(&s.board)?;
            ops::execute(&mut s.board, Origin::User, Command::Restore(Box::new(snap)))?;
            s.history.finish_redo();
            s.dirty = true;
            Ok(label)
        })
    }

    pub fn clear_history(&self) {
        self.lock().history.clear();
    }

    /// The open project's directory, if the board has been saved in one.
    pub fn project_dir(&self) -> Option<PathBuf> {
        let s = self.lock();
        s.path
            .as_ref()
            .and_then(|p| p.parent())
            .map(Path::to_path_buf)
    }

    /// Open the project in `dir`, which must hold a `stickynotes.json`.
    pub fn open_project(&self, dir: &Path) -> Result<()> {
        if !project::is_project(dir) {
            return Err(Error::NotAProject(dir.to_path_buf()));
        }
        project::ensure_dirs(dir)?;
        self.open(&project::board_path(dir))
    }

    /// Create a project in `dir` (new or empty) and open it. With nothing
    /// open yet and unsaved edits, the project adopts the board as it is;
    /// otherwise it starts from a fresh board titled `title`.
    pub fn create_project(&self, dir: &Path, title: &str) -> Result<()> {
        if project::is_project(dir) || !project::is_empty_dir(dir) {
            return Err(Error::Validation(format!(
                "{} already has files in it",
                dir.display()
            )));
        }
        project::ensure_dirs(dir)?;
        self.mutate(Origin::User, |s| {
            s.history.clear();
            s.reset_backups();
            if !(s.path.is_none() && s.dirty) {
                s.board = Board::new_default();
                s.board.title = title.to_string();
            }
            let path = project::board_path(dir);
            s.stamp = s.save_to(&path)?;
            s.path = Some(path);
            s.dirty = false;
            Ok(())
        })
    }

    /// Open `dir` if it is a project, or turn a new or empty folder into one
    /// named after the folder.
    pub fn open_or_create_project(&self, dir: &Path) -> Result<()> {
        if project::is_project(dir) {
            self.open_project(dir)
        } else if project::is_empty_dir(dir) {
            let title = dir
                .file_name()
                .map_or_else(|| "Untitled board".into(), |n| n.to_string_lossy());
            self.create_project(dir, &title)
        } else {
            Err(Error::NotAProject(dir.to_path_buf()))
        }
    }

    pub fn open(&self, path: &Path) -> Result<()> {
        let (mut board, stamp) = persist::load(path)?;
        // Boards from before task numbers get numbered here; leave them
        // marked unsaved so the numbers are written out and stay stable.
        let backfilled = board.normalize();
        self.mutate(Origin::User, |s| {
            s.history.clear();
            s.reset_backups();
            s.board = board;
            s.path = Some(path.to_path_buf());
            s.stamp = stamp;
            s.dirty = backfilled;
            Ok(())
        })
    }

    /// Save to the current path. Unless `force`, refuses to overwrite a file
    /// that changed on disk since it was loaded or last saved.
    pub fn save(&self, force: bool) -> Result<()> {
        self.mutate(Origin::User, |s| {
            let path = s.path.clone().ok_or(Error::NoPath)?;
            if !force && s.stamp.is_some() && FileStamp::of(&path) != s.stamp {
                return Err(Error::ModifiedOnDisk(path));
            }
            s.stamp = s.save_to(&path)?;
            s.dirty = false;
            Ok(())
        })
    }

    /// Replace the clock used to name and space backups (for tests).
    pub fn set_clock(&self, clock: impl Fn() -> DateTime<Local> + Send + Sync + 'static) {
        self.lock().clock = Box::new(clock);
    }

    /// A backup problem found by a save, reported once per opened project.
    pub fn take_backup_notice(&self) -> Option<String> {
        self.lock().backup_notice.take()
    }

    /// The backups of the open board, newest first.
    pub fn list_backups(&self) -> Vec<backup::BackupInfo> {
        self.lock()
            .path
            .as_deref()
            .map(backup::list)
            .unwrap_or_default()
    }

    /// Replace the open board with the backup `name`. The file on disk is
    /// snapshotted first; the restored board is left unsaved and the undo
    /// history is cleared.
    pub fn restore_backup(&self, name: &str) -> Result<()> {
        self.mutate(Origin::User, |s| {
            let path = s.path.clone().ok_or(Error::NoPath)?;
            let mut board = backup::read(&path, name)?;
            backup::snapshot_now(&path, (s.clock)())?;
            board.normalize();
            s.board = board;
            s.stamp = FileStamp::of(&path);
            s.dirty = true;
            s.history.clear();
            Ok(())
        })
    }

    pub fn save_as(&self, path: &Path) -> Result<()> {
        self.mutate(Origin::User, |s| {
            s.reset_backups();
            s.stamp = s.save_to(path)?;
            s.path = Some(path.to_path_buf());
            s.dirty = false;
            Ok(())
        })
    }

    /// Save `data` as a new file in the project's `artifacts/` folder and
    /// attach it to `task`. `name` is cleaned up (see [`artifact::clean_name`])
    /// and made unique; the attached [`Artifact`] says what it ended up as.
    /// The file is written at once; the record is saved with the board.
    pub fn add_artifact(
        &self,
        origin: Origin,
        task: TaskId,
        name: &str,
        data: &[u8],
        expected_revision: Option<u64>,
    ) -> Result<(Artifact, u64)> {
        self.add_artifact_as(origin, None, task, name, data, expected_revision)
    }

    /// Like [`add_artifact`](Self::add_artifact), recording `client` (an
    /// agent's name) as who added it; ignored for the user.
    pub fn add_artifact_as(
        &self,
        origin: Origin,
        client: Option<String>,
        task: TaskId,
        name: &str,
        data: &[u8],
        expected_revision: Option<u64>,
    ) -> Result<(Artifact, u64)> {
        if origin == Origin::Agent && !self.agent_write() {
            return Err(Error::AgentWriteDisabled);
        }
        let (file_name, kind) = artifact::clean_name(name)?;
        artifact::validate_content(&file_name, kind, data)?;
        let dir = self.project_dir().ok_or(Error::NoPath)?;
        if self.read(|board, _| board.task(task).is_none()) {
            return Err(Error::not_found("task", task));
        }
        let stored = artifact::write_new(&dir, &file_name, data)?;
        let record = Artifact {
            id: uuid::Uuid::new_v4(),
            name: stored.clone(),
            kind,
            added_at: chrono::Utc::now(),
            by_agent: origin == Origin::Agent,
            added_by: None,
            stage: None,
            extra: Default::default(),
        };
        let cmd = Command::AttachArtifact {
            task,
            artifact: record,
            added_by: client.clone(),
        };
        match self.apply_as(origin, client.as_deref(), cmd, expected_revision) {
            Ok((_, revision)) => {
                // The core filled in who and stage; read the stored record.
                let record = self
                    .read(|board, _| {
                        board
                            .task(task)
                            .and_then(|t| t.artifacts.iter().find(|a| a.name == stored).cloned())
                    })
                    .ok_or_else(|| Error::not_found("task", task))?;
                Ok((record, revision))
            }
            Err(e) => {
                artifact::remove(&dir, &stored);
                Err(e)
            }
        }
    }

    /// Where a file in the project's `artifacts/` folder is on disk.
    pub fn artifact_path(&self, file_name: &str) -> Result<PathBuf> {
        let dir = self.project_dir().ok_or(Error::NoPath)?;
        artifact::locate(&dir, file_name)
    }

    /// The bytes of a file in the project's `artifacts/` folder.
    pub fn read_artifact(&self, file_name: &str) -> Result<Vec<u8>> {
        let dir = self.project_dir().ok_or(Error::NoPath)?;
        artifact::read(&dir, file_name)
    }

    /// Every file in `artifacts/`, with the tasks it is attached to. Files
    /// no task points at (detached, or left by a deleted task) are listed too.
    pub fn artifact_files(&self) -> Vec<ArtifactFile> {
        let Some(dir) = self.project_dir() else {
            return Vec::new();
        };
        let stored = artifact::list_files(&dir);
        self.read(|board, _| {
            stored
                .into_iter()
                .map(|file| {
                    let mut added = Vec::new();
                    let tasks = board
                        .tasks()
                        .filter_map(|(_, t)| {
                            t.artifacts.iter().find(|a| a.name == file.name).map(|a| {
                                added.push(a.added_at.timestamp_millis());
                                (t.id, t.number, a.id)
                            })
                        })
                        .collect();
                    let at_ms = added.into_iter().min().unwrap_or(file.modified_ms);
                    ArtifactFile { file, tasks, at_ms }
                })
                .collect()
        })
    }

    pub fn to_markdown(&self) -> String {
        export_md::to_markdown(&self.lock().board)
    }

    pub fn export_markdown(&self, path: &Path) -> Result<()> {
        persist::write_atomic(path, self.to_markdown().as_bytes())
    }

    /// A Claude Code skill describing the board and the project's instructions.
    pub fn to_skill_markdown(&self) -> String {
        agent_guide::skill_markdown(&self.lock().board)
    }

    /// Write the skill file, creating its folder if needed.
    pub fn export_skill(&self, path: &Path) -> Result<()> {
        if let Some(dir) = path.parent().filter(|d| !d.as_os_str().is_empty()) {
            std::fs::create_dir_all(dir).map_err(|source| Error::Io {
                path: dir.to_path_buf(),
                source,
            })?;
        }
        persist::write_atomic(path, self.to_skill_markdown().as_bytes())
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        relock(&self.state)
    }

    /// Run `f` under the lock; on success bump the revision and notify
    /// listeners (after releasing the lock, so listeners may read the store).
    ///
    /// A panic in `f` does not poison the store: `relock` recovers the lock.
    /// For the state to stay consistent afterwards, commands must validate
    /// before they mutate, so `f` never panics half-way through a change.
    fn mutate<R>(&self, origin: Origin, f: impl FnOnce(&mut State) -> Result<R>) -> Result<R> {
        let (result, change) = {
            let mut s = self.lock();
            let result = f(&mut s)?;
            s.revision += 1;
            (
                result,
                Change {
                    revision: s.revision,
                    origin,
                },
            )
        };
        for listener in relock(&self.listeners).iter() {
            listener(change);
        }
        Ok(result)
    }
}

/// Lock a mutex, recovering the data if another thread panicked while holding it.
pub fn relock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(PoisonError::into_inner)
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicU64, Ordering};

    use super::*;
    use crate::command::TaskDraft;

    #[test]
    fn a_panic_inside_mutate_does_not_brick_the_store() {
        let dir = tempfile::tempdir().unwrap();
        let store = BoardStore::new(true);
        store.save_as(&dir.path().join("board.json")).unwrap();
        let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = store.mutate::<()>(Origin::User, |_| panic!("boom"));
        }));
        assert!(caught.is_err());
        assert!(store.state.is_poisoned());
        let rev = store.snapshot().revision;
        store.apply(Origin::User, create(), None).unwrap();
        assert_eq!(store.snapshot().revision, rev + 1);
        store.save(true).unwrap();
    }

    #[test]
    fn move_tasks_is_one_revision_and_one_notification() {
        let store = BoardStore::new(true);
        let mut ids = vec![];
        for _ in 0..3 {
            let (Applied::Task(id), _) = store.apply(Origin::User, create(), None).unwrap() else {
                panic!()
            };
            ids.push(id);
        }
        let calls = std::sync::Arc::new(AtomicU64::new(0));
        let seen = calls.clone();
        store.subscribe(move |_| {
            seen.fetch_add(1, Ordering::SeqCst);
        });
        let rev = store.snapshot().revision;
        let to = store.snapshot().board.columns[1].id;
        store
            .apply(
                Origin::User,
                Command::MoveTasks {
                    ids,
                    to_column: to,
                    position: 0,
                },
                None,
            )
            .unwrap();
        assert_eq!(store.snapshot().revision, rev + 1);
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }

    fn create() -> Command {
        Command::CreateTask {
            column: None,
            position: None,
            draft: TaskDraft {
                description: "t".into(),
                ..Default::default()
            },
        }
    }

    #[test]
    fn category_commands_go_through_apply() {
        let store = BoardStore::new(true);
        let mk = |origin, c: &str| {
            store
                .apply(
                    origin,
                    Command::CreateTask {
                        column: None,
                        position: None,
                        draft: TaskDraft {
                            description: "t".into(),
                            category: Some(c.into()),
                            ..Default::default()
                        },
                    },
                    None,
                )
                .unwrap()
        };
        mk(Origin::User, "UI");
        let rev = store.revision();
        mk(Origin::Agent, " ui ");
        assert_eq!(store.revision(), rev + 1);
        let cats = store.read(|b, _| {
            b.tasks()
                .map(|(_, t)| t.category.clone())
                .collect::<Vec<_>>()
        });
        assert_eq!(cats, vec![Some("UI".to_string()), Some("UI".to_string())]);
    }

    #[test]
    fn agent_writes_are_gated() {
        let store = BoardStore::new(false);
        let rev = store.revision();
        assert!(matches!(
            store.apply(Origin::Agent, create(), None),
            Err(Error::AgentWriteDisabled)
        ));
        assert_eq!(store.revision(), rev);
        store.apply(Origin::User, create(), None).unwrap();
        store.set_agent_write(true);
        store.apply(Origin::Agent, create(), None).unwrap();
    }

    #[test]
    fn revision_conflicts_are_detected() {
        let store = BoardStore::new(true);
        let rev = store.revision();
        let (_, new_rev) = store.apply(Origin::Agent, create(), Some(rev)).unwrap();
        assert_eq!(new_rev, rev + 1);
        assert!(matches!(
            store.apply(Origin::Agent, create(), Some(rev)),
            Err(Error::RevisionConflict { .. })
        ));
    }

    #[test]
    fn listeners_see_changes() {
        let store = BoardStore::new(true);
        let seen = Arc::new(AtomicU64::new(0));
        let s = seen.clone();
        store.subscribe(move |c| s.store(c.revision, Ordering::SeqCst));
        store.apply(Origin::User, create(), None).unwrap();
        assert_eq!(seen.load(Ordering::SeqCst), store.revision());
    }

    #[test]
    fn save_open_and_dirty_tracking() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.json");
        let store = BoardStore::new(false);
        assert!(matches!(store.save(false), Err(Error::NoPath)));

        store.apply(Origin::User, create(), None).unwrap();
        assert!(store.snapshot().dirty);
        store.save_as(&path).unwrap();
        assert!(!store.snapshot().dirty);

        let other = BoardStore::new(false);
        other.open(&path).unwrap();
        assert_eq!(other.snapshot().board, store.snapshot().board);
    }

    #[test]
    fn creating_a_project_makes_the_folders_and_opens_it() {
        let root = tempfile::tempdir().unwrap();
        let dir = root.path().join("demo");
        let store = BoardStore::new(false);
        store.create_project(&dir, "Demo").unwrap();

        assert!(project::is_project(&dir));
        assert!(project::artifacts_dir(&dir).is_dir());
        assert_eq!(store.project_dir(), Some(dir.clone()));
        let snap = store.snapshot();
        assert_eq!(snap.board.title, "Demo");
        assert!(!snap.dirty);

        let other = BoardStore::new(false);
        other.open_project(&dir).unwrap();
        assert_eq!(other.snapshot().board.title, "Demo");
        assert!(matches!(
            other.create_project(&dir, "Again"),
            Err(Error::Validation(_))
        ));
    }

    #[test]
    fn an_unsaved_untitled_board_is_adopted_by_the_first_project() {
        let root = tempfile::tempdir().unwrap();
        let store = BoardStore::new(false);
        store.apply(Origin::User, create(), None).unwrap();
        store.create_project(&root.path().join("p"), "P").unwrap();
        let snap = store.snapshot();
        assert_eq!(snap.board.tasks().count(), 1);
        assert_eq!(snap.board.title, "Untitled board");
    }

    #[test]
    fn open_or_create_refuses_folders_with_other_files() {
        let root = tempfile::tempdir().unwrap();
        let store = BoardStore::new(false);
        let missing = root.path().join("new");
        store.open_or_create_project(&missing).unwrap();
        assert_eq!(store.snapshot().board.title, "new");

        let busy = root.path().join("busy");
        std::fs::create_dir(&busy).unwrap();
        std::fs::write(busy.join("notes.txt"), "x").unwrap();
        assert!(matches!(
            store.open_or_create_project(&busy),
            Err(Error::NotAProject(_))
        ));
        assert!(matches!(
            store.open_project(&busy),
            Err(Error::NotAProject(_))
        ));
    }

    #[test]
    fn save_detects_outside_modification() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.json");
        let store = BoardStore::new(false);
        store.save_as(&path).unwrap();
        std::fs::write(&path, "{ \"changed\": true, \"padding\": 1 }").unwrap();
        assert!(matches!(store.save(false), Err(Error::ModifiedOnDisk(_))));
        store.save(true).unwrap();
    }

    #[test]
    fn export_skill_creates_folders_and_reflects_project_settings() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(".claude/skills/stickynotes/SKILL.md");
        let store = BoardStore::new(false);
        store
            .apply(
                Origin::User,
                Command::UpdateProject {
                    title: None,
                    document_prompt: Some("Be brief.".into()),
                    code_guidance: None,
                },
                None,
            )
            .unwrap();
        store.export_skill(&path).unwrap();
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(text.contains("name: stickynotes-board") && text.contains("Be brief."));
    }

    #[test]
    fn opening_an_old_board_numbers_it_and_marks_it_unsaved() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("old.json");
        // A saved board whose tasks have no numbers, as before numbering existed.
        let store = BoardStore::new(false);
        store.apply(Origin::User, create(), None).unwrap();
        store.apply(Origin::User, create(), None).unwrap();
        let mut value = serde_json::to_value(store.snapshot().board).unwrap();
        value.as_object_mut().unwrap().remove("next_number");
        for column in value["columns"].as_array_mut().unwrap() {
            for task in column["tasks"].as_array_mut().unwrap() {
                task.as_object_mut().unwrap().remove("number");
            }
        }
        std::fs::write(&path, serde_json::to_vec(&value).unwrap()).unwrap();

        let opened = BoardStore::new(false);
        opened.open(&path).unwrap();
        let snap = opened.snapshot();
        let numbers: Vec<_> = snap.board.tasks().map(|(_, t)| t.number).collect();
        assert_eq!(numbers, [1, 2]);
        assert!(snap.dirty, "backfilled numbers still need saving");

        // Saved, they stay put across a reload, and new tasks continue after them.
        opened.save(false).unwrap();
        let reopened = BoardStore::new(false);
        reopened.open(&path).unwrap();
        let snap = reopened.snapshot();
        assert!(!snap.dirty);
        let numbers: Vec<_> = snap.board.tasks().map(|(_, t)| t.number).collect();
        assert_eq!(numbers, [1, 2]);
        reopened.apply(Origin::User, create(), None).unwrap();
        assert!(reopened.snapshot().board.find_by_number(3).is_some());
    }

    #[test]
    fn a_numbered_board_opens_clean() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.json");
        let store = BoardStore::new(false);
        store.apply(Origin::User, create(), None).unwrap();
        store.save_as(&path).unwrap();
        let other = BoardStore::new(false);
        other.open(&path).unwrap();
        assert!(!other.snapshot().dirty);
        assert_eq!(other.snapshot().board, store.snapshot().board);
    }

    // ---- artifacts ----

    fn project_store() -> (tempfile::TempDir, Arc<BoardStore>, TaskId) {
        let root = tempfile::tempdir().unwrap();
        let store = BoardStore::new(true);
        store.create_project(&root.path().join("p"), "P").unwrap();
        let (applied, _) = store.apply(Origin::User, create(), None).unwrap();
        let Applied::Task(id) = applied else { panic!() };
        (root, store, id)
    }

    #[test]
    fn attaching_writes_the_file_and_records_it_on_the_task() {
        let (_root, store, task) = project_store();
        let (art, _) = store
            .add_artifact(Origin::Agent, task, "Plan v1.md", b"# Plan", None)
            .unwrap();
        assert_eq!(art.name, "Plan-v1.md");
        assert!(art.by_agent);
        assert_eq!(store.read_artifact("Plan-v1.md").unwrap(), b"# Plan");
        let snap = store.snapshot();
        assert_eq!(
            snap.board.task(task).unwrap().artifacts,
            std::slice::from_ref(&art)
        );
        assert!(snap.dirty);
        assert!(snap.board.task(task).unwrap().agent_change.is_some());

        // The record survives a save and reload.
        store.save(false).unwrap();
        let other = BoardStore::new(false);
        other.open_project(&store.project_dir().unwrap()).unwrap();
        assert_eq!(other.snapshot().board.task(task).unwrap().artifacts, [art]);
    }

    #[test]
    fn same_name_twice_gets_a_new_file() {
        let (_root, store, task) = project_store();
        let (a, _) = store
            .add_artifact(Origin::User, task, "n.md", b"one", None)
            .unwrap();
        let (b, _) = store
            .add_artifact(Origin::User, task, "n.md", b"two", None)
            .unwrap();
        assert_eq!((a.name.as_str(), b.name.as_str()), ("n.md", "n-2.md"));
        assert_eq!(store.read_artifact("n.md").unwrap(), b"one");
    }

    #[test]
    fn detaching_keeps_the_file_and_lists_it_as_unattached() {
        let (_root, store, task) = project_store();
        let (art, _) = store
            .add_artifact(Origin::Agent, task, "n.md", b"x", None)
            .unwrap();
        let files = store.artifact_files();
        assert_eq!(files[0].tasks.len(), 1);

        store
            .apply(
                Origin::Agent,
                Command::DetachArtifact {
                    task,
                    artifact: art.id,
                },
                None,
            )
            .unwrap();
        assert!(
            store
                .snapshot()
                .board
                .task(task)
                .unwrap()
                .artifacts
                .is_empty()
        );
        let files = store.artifact_files();
        assert_eq!(files.len(), 1);
        assert!(files[0].tasks.is_empty());
        assert!(store.read_artifact("n.md").is_ok());
    }

    #[test]
    fn a_rejected_attach_leaves_no_file_behind() {
        let (_root, store, task) = project_store();
        let stale = store.revision() - 1;
        let err = store
            .add_artifact(Origin::Agent, task, "n.md", b"x", Some(stale))
            .unwrap_err();
        assert!(matches!(err, Error::RevisionConflict { .. }));
        assert!(store.artifact_files().is_empty());

        store.set_agent_write(false);
        let err = store
            .add_artifact(Origin::Agent, task, "n.md", b"x", None)
            .unwrap_err();
        assert!(matches!(err, Error::AgentWriteDisabled));
        assert!(store.artifact_files().is_empty());
    }

    #[test]
    fn attaching_needs_a_project_a_task_and_good_content() {
        let (_root, store, task) = project_store();
        let missing = uuid::Uuid::new_v4();
        assert!(matches!(
            store.add_artifact(Origin::User, missing, "n.md", b"x", None),
            Err(Error::NotFound { .. })
        ));
        assert!(
            store
                .add_artifact(Origin::User, task, "n.exe", b"x", None)
                .is_err()
        );
        assert!(
            store
                .add_artifact(Origin::User, task, "n.png", b"not a png", None)
                .is_err()
        );

        let loose = BoardStore::new(true);
        let (applied, _) = loose.apply(Origin::User, create(), None).unwrap();
        let Applied::Task(id) = applied else { panic!() };
        assert!(matches!(
            loose.add_artifact(Origin::User, id, "n.md", b"x", None),
            Err(Error::NoPath)
        ));
    }

    #[test]
    fn a_pdf_attaches_survives_a_reload_and_detaches_leaving_the_file() {
        use crate::model::ArtifactKind;
        let (_root, store, task) = project_store();
        let (artifact, _) = store
            .add_artifact(Origin::User, task, "Spec.pdf", b"%PDF-1.4 body", None)
            .unwrap();
        assert_eq!(
            (artifact.name.as_str(), artifact.kind),
            ("Spec.pdf", ArtifactKind::Pdf)
        );
        assert!(
            store
                .add_artifact(Origin::User, task, "fake.pdf", b"<html>", None)
                .is_err()
        );
        store.save(false).unwrap();

        let dir = store.project_dir().unwrap();
        let reopened = BoardStore::new(true);
        reopened.open_project(&dir).unwrap();
        let kinds = reopened.read(|b, _| {
            b.task(task)
                .unwrap()
                .artifacts
                .iter()
                .map(|a| a.kind)
                .collect::<Vec<_>>()
        });
        assert_eq!(kinds, [ArtifactKind::Pdf]);
        assert!(reopened.artifact_path("Spec.pdf").is_ok());

        reopened
            .apply(
                Origin::User,
                Command::DetachArtifact {
                    task,
                    artifact: artifact.id,
                },
                None,
            )
            .unwrap();
        assert!(reopened.read(|b, _| b.task(task).unwrap().artifacts.is_empty()));
        assert!(reopened.artifact_path("Spec.pdf").is_ok(), "the file stays");
    }

    #[test]
    fn a_task_has_a_limited_number_of_artifacts() {
        let (_root, store, task) = project_store();
        for i in 0..artifact::MAX_PER_TASK {
            store
                .add_artifact(Origin::User, task, &format!("n{i}.md"), b"x", None)
                .unwrap();
        }
        assert!(matches!(
            store.add_artifact(Origin::User, task, "extra.md", b"x", None),
            Err(Error::Validation(_))
        ));
        assert_eq!(store.artifact_files().len(), artifact::MAX_PER_TASK);
    }

    #[test]
    fn boards_without_artifacts_load_and_stay_unchanged_on_disk() {
        let (_root, store, _) = project_store();
        store.save(false).unwrap();
        let text =
            std::fs::read_to_string(project::board_path(&store.project_dir().unwrap())).unwrap();
        assert!(
            !text.contains("artifacts"),
            "no empty artifacts field is written"
        );
    }

    #[test]
    fn attaching_records_who_and_the_stage_as_a_snapshot() {
        let (_dir, store, task) = project_store();
        let column = store.snapshot().board.columns[0].id;
        let (art, _) = store
            .add_artifact_as(
                Origin::Agent,
                Some("claude-code".into()),
                task,
                "a.md",
                b"x",
                None,
            )
            .unwrap();
        let first = store.snapshot().board.columns[0].title.clone();
        assert_eq!(art.stage.as_deref(), Some(first.as_str()));
        assert_eq!(art.added_by.as_deref(), Some("claude-code"));
        let (mine, _) = store
            .add_artifact_as(
                Origin::User,
                Some("ignored".into()),
                task,
                "b.md",
                b"x",
                None,
            )
            .unwrap();
        assert_eq!(mine.added_by.as_deref(), Some("user"));
        assert!(!mine.by_agent);
        let (anon, _) = store
            .add_artifact(Origin::Agent, task, "c.md", b"x", None)
            .unwrap();
        assert_eq!(anon.added_by.as_deref(), Some("agent"));

        store
            .apply(
                Origin::User,
                Command::UpdateColumn {
                    id: column,
                    title: Some("Renamed".into()),
                    description: None,
                },
                None,
            )
            .unwrap();
        let snap = store.snapshot();
        let stored = &snap.board.task(task).unwrap().artifacts[0];
        assert_eq!(stored.stage.as_deref(), Some(first.as_str()));
    }

    #[test]
    fn an_old_artifact_record_loads_and_saves_without_the_new_fields() {
        let old = serde_json::json!({
            "id": uuid::Uuid::new_v4(),
            "name": "n.md",
            "kind": "markdown",
            "added_at": "2026-01-01T00:00:00Z",
            "by_agent": true
        });
        let a: Artifact = serde_json::from_value(old.clone()).unwrap();
        assert!(a.added_by.is_none() && a.stage.is_none());
        let back = serde_json::to_value(&a).unwrap();
        assert!(back.get("added_by").is_none() && back.get("stage").is_none());
        assert_eq!(back["by_agent"], true);
    }

    fn activity_store() -> (tempfile::TempDir, Arc<BoardStore>) {
        let root = tempfile::tempdir().unwrap();
        let store = BoardStore::new(true);
        store.create_project(&root.path().join("p"), "P").unwrap();
        (root, store)
    }

    fn log(root: &tempfile::TempDir) -> Vec<crate::activity::Entry> {
        crate::activity::read(&root.path().join("p"))
    }

    #[test]
    fn each_kind_of_agent_command_writes_one_entry() {
        use crate::command::{CriterionDraft, TaskPatch};
        let (root, store) = activity_store();
        let agent = |cmd| {
            store
                .apply_as(Origin::Agent, Some("claude-code"), cmd, None)
                .unwrap()
        };
        let (Applied::Task(id), _) = agent(Command::CreateTask {
            column: None,
            position: None,
            draft: TaskDraft {
                description: "Fix login".into(),
                extended_description: "SECRET detail".into(),
                acceptance_criteria: vec![CriterionDraft {
                    text: "SECRET criterion".into(),
                    ..Default::default()
                }],
                ..Default::default()
            },
        }) else {
            panic!()
        };
        agent(Command::UpdateTask {
            id,
            patch: TaskPatch {
                description: Some("Fix the login".into()),
                ..Default::default()
            },
        });
        let cid = store.snapshot().board.task(id).unwrap().acceptance_criteria[0].id;
        for done in [true, true, false] {
            agent(Command::SetCriterion {
                task: id,
                criterion: cid,
                done,
            });
        }
        agent(Command::AdvanceTask { id });
        let record = Artifact {
            id: uuid::Uuid::new_v4(),
            name: "n.md".into(),
            kind: crate::model::ArtifactKind::Markdown,
            added_at: chrono::Utc::now(),
            by_agent: true,
            added_by: None,
            stage: None,
            extra: Default::default(),
        };
        let aid = record.id;
        agent(Command::AttachArtifact {
            task: id,
            artifact: record,
            added_by: None,
        });
        agent(Command::DetachArtifact {
            task: id,
            artifact: aid,
        });
        agent(Command::DeleteTask { id });
        let entries = log(&root);
        let actions: Vec<_> = entries.iter().map(|e| e.action.as_str()).collect();
        assert_eq!(
            actions,
            [
                "created", "updated", "ticked", "unticked", "advanced", "attached", "detached",
                "deleted"
            ]
        );
        assert!(
            entries
                .iter()
                .all(|e| e.agent == "claude-code" && e.task == 1)
        );
        assert_eq!(entries[1].title, "Fix the login");
        assert_eq!(entries[7].title, "Fix the login");
        assert_eq!(entries[4].to.as_deref(), Some("To Do"));
        let raw = std::fs::read_to_string(root.path().join("p").join("activity.jsonl")).unwrap();
        assert!(!raw.contains("SECRET"));
    }

    #[test]
    fn unnamed_agent_is_called_agent() {
        let (root, store) = activity_store();
        store.apply(Origin::Agent, create(), None).unwrap();
        assert_eq!(log(&root)[0].agent, "agent");
    }

    #[test]
    fn user_rejected_and_unsaved_write_nothing() {
        let (root, store) = activity_store();
        store.apply(Origin::User, create(), None).unwrap();
        let rev = store.snapshot().revision;
        let bad = Command::AdvanceTask {
            id: uuid::Uuid::new_v4(),
        };
        assert!(store.apply(Origin::Agent, bad, None).is_err());
        assert!(store.apply(Origin::Agent, create(), Some(rev + 9)).is_err());
        store.set_agent_write(false);
        assert!(store.apply(Origin::Agent, create(), None).is_err());
        assert!(log(&root).is_empty());
        assert!(!root.path().join("p").join("activity.jsonl").exists());
        // No project folder: applying still works and nothing is written.
        let loose = BoardStore::new(true);
        loose.apply(Origin::Agent, create(), None).unwrap();
    }
}
