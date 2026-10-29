//! The single source of truth shared by the UI and the agent API.
//!
//! `BoardStore` owns the open board plus session state (file path, dirty
//! flag, revision, agent write access). Every mutation goes through
//! [`BoardStore::apply`]; listeners are notified after each change.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};

use crate::command::{Applied, Command, Origin};
use crate::error::{Error, Result};
use crate::model::Board;
use crate::ops;
use crate::persist::{self, FileStamp};
use crate::{agent_guide, export_md};

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

type Listener = Box<dyn Fn(Change) + Send + Sync>;

struct State {
    board: Board,
    path: Option<PathBuf>,
    stamp: Option<FileStamp>,
    dirty: bool,
    revision: u64,
    agent_write: bool,
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
            }),
            listeners: Mutex::new(Vec::new()),
        })
    }

    /// Register a callback run (on the mutating thread) after every change.
    pub fn subscribe(&self, listener: impl Fn(Change) + Send + Sync + 'static) {
        self.listeners.lock().unwrap().push(Box::new(listener));
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
            let applied = ops::execute(&mut s.board, origin, cmd)?;
            s.dirty = true;
            Ok((applied, s.revision + 1))
        })
    }

    /// Replace the board with a fresh default board.
    pub fn new_board(&self) {
        self.mutate(Origin::User, |s| {
            s.board = Board::new_default();
            s.path = None;
            s.stamp = None;
            s.dirty = false;
            Ok(())
        })
        .expect("infallible");
    }

    pub fn open(&self, path: &Path) -> Result<()> {
        let (mut board, stamp) = persist::load(path)?;
        // Boards from before task numbers get numbered here; leave them
        // marked unsaved so the numbers are written out and stay stable.
        let backfilled = board.normalize();
        self.mutate(Origin::User, |s| {
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
            s.stamp = persist::save(&path, &s.board)?;
            s.dirty = false;
            Ok(())
        })
    }

    pub fn save_as(&self, path: &Path) -> Result<()> {
        self.mutate(Origin::User, |s| {
            s.stamp = persist::save(path, &s.board)?;
            s.path = Some(path.to_path_buf());
            s.dirty = false;
            Ok(())
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
        self.state.lock().unwrap()
    }

    /// Run `f` under the lock; on success bump the revision and notify
    /// listeners (after releasing the lock, so listeners may read the store).
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
        for listener in self.listeners.lock().unwrap().iter() {
            listener(change);
        }
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicU64, Ordering};

    use super::*;
    use crate::command::TaskDraft;

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
}
