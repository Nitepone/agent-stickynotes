//! Rolling backups of the board file.
//!
//! Before a save replaces the board file, its previous contents are kept as
//! `<file>.bak` next to it and, at most once per [`SNAPSHOT_INTERVAL`] (and
//! always on the first save after a project is opened), as a timestamped copy
//! in the project's `backups/` folder. The newest [`MAX_SNAPSHOTS`] copies
//! are kept. Failures here never fail a save; they are returned for the
//! caller to report.

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Duration, Local, NaiveDateTime, TimeZone};

use crate::error::{Error, Result};
use crate::model::Board;
use crate::persist::{load, write_atomic};

pub const DIR: &str = "backups";
pub const MAX_SNAPSHOTS: usize = 20;
const STAMP_FORMAT: &str = "%Y%m%d-%H%M%S";

/// Least time between two snapshots.
pub fn snapshot_interval() -> Duration {
    Duration::minutes(10)
}

/// One restorable file.
#[derive(Debug, Clone, PartialEq)]
pub struct BackupInfo {
    /// File name: the `.bak` name or `board-YYYYMMDD-HHMMSS.json`.
    pub name: String,
    pub time: DateTime<Local>,
    /// `None` when the file cannot be read as a board.
    pub tasks: Option<usize>,
}

impl BackupInfo {
    /// The time as shown to the user, in local time.
    pub fn time_label(&self) -> String {
        self.time.format("%Y-%m-%d %H:%M:%S").to_string()
    }
}

fn bak_path(path: &Path) -> PathBuf {
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(".bak");
    path.with_file_name(name)
}

fn dir_of(path: &Path) -> PathBuf {
    path.parent()
        .filter(|d| !d.as_os_str().is_empty())
        .unwrap_or(Path::new("."))
        .join(DIR)
}

fn is_snapshot_name(name: &str) -> bool {
    snapshot_time(name).is_some()
}

fn snapshot_time(name: &str) -> Option<DateTime<Local>> {
    let stamp = name.strip_prefix("board-")?.strip_suffix(".json")?;
    let naive = NaiveDateTime::parse_from_str(stamp, STAMP_FORMAT).ok()?;
    Local.from_local_datetime(&naive).earliest()
}

fn io_err(path: &Path, source: std::io::Error) -> Error {
    Error::Io {
        path: path.to_path_buf(),
        source,
    }
}

/// Copy `bytes` into `backups/`, never overwriting a snapshot.
fn write_snapshot(path: &Path, bytes: &[u8], mut when: DateTime<Local>) -> Result<()> {
    let dir = dir_of(path);
    fs::create_dir_all(&dir).map_err(|e| io_err(&dir, e))?;
    loop {
        let target = dir.join(format!("board-{}.json", when.format(STAMP_FORMAT)));
        if !target.exists() {
            return write_atomic(&target, bytes);
        }
        when += Duration::seconds(1);
    }
}

fn prune(path: &Path) -> Result<()> {
    let dir = dir_of(path);
    let mut names: Vec<String> = fs::read_dir(&dir)
        .map_err(|e| io_err(&dir, e))?
        .filter_map(|e| e.ok()?.file_name().into_string().ok())
        .filter(|n| is_snapshot_name(n))
        .collect();
    names.sort();
    let excess = names.len().saturating_sub(MAX_SNAPSHOTS);
    for name in &names[..excess] {
        let file = dir.join(name);
        fs::remove_file(&file).map_err(|e| io_err(&file, e))?;
    }
    Ok(())
}

/// Back up the file at `path` before a save replaces it. `last` is when the
/// previous snapshot was taken (`None`: none yet since the project opened);
/// it is updated when one is taken now. Returns the first failure, if any,
/// after attempting everything.
pub fn before_save(
    path: &Path,
    now: DateTime<Local>,
    last: &mut Option<DateTime<Local>>,
) -> Result<()> {
    let Ok(old) = fs::read(path) else {
        return Ok(()); // nothing there yet (first save)
    };
    let mut first_error = write_atomic(&bak_path(path), &old).err();
    if last.is_none_or(|t| now - t >= snapshot_interval()) {
        match write_snapshot(path, &old, now).and_then(|()| prune(path)) {
            Ok(()) => *last = Some(now),
            Err(e) => first_error = first_error.or(Some(e)),
        }
    }
    first_error.map_or(Ok(()), Err)
}

/// Snapshot the current file regardless of the interval (before a restore).
pub fn snapshot_now(path: &Path, now: DateTime<Local>) -> Result<()> {
    let Ok(old) = fs::read(path) else {
        return Ok(());
    };
    write_snapshot(path, &old, now)?;
    prune(path)
}

/// The restorable files for the board at `path`, newest first.
pub fn list(path: &Path) -> Vec<BackupInfo> {
    let mut found = Vec::new();
    let mut add = |file: PathBuf, name: String, time: Option<DateTime<Local>>| {
        let time = time
            .or_else(|| {
                let modified = fs::metadata(&file).ok()?.modified().ok()?;
                Some(DateTime::<Local>::from(modified))
            })
            .unwrap_or_default();
        let tasks = load(&file)
            .ok()
            .map(|(b, _)| b.columns.iter().map(|c| c.tasks.len()).sum());
        found.push(BackupInfo { name, time, tasks });
    };
    let bak = bak_path(path);
    if bak.is_file() {
        let name = bak.file_name().unwrap().to_string_lossy().into_owned();
        add(bak, name, None);
    }
    if let Ok(entries) = fs::read_dir(dir_of(path)) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if let Some(time) = snapshot_time(&name) {
                add(entry.path(), name, Some(time));
            }
        }
    }
    found.sort_by(|a, b| b.time.cmp(&a.time).then_with(|| b.name.cmp(&a.name)));
    found
}

/// Read the backup called `name` (as listed by [`list`]) as a board.
pub fn read(path: &Path, name: &str) -> Result<Board> {
    if !list(path).iter().any(|b| b.name == name) {
        return Err(Error::not_found("backup", name));
    }
    let file = if is_snapshot_name(name) {
        dir_of(path).join(name)
    } else {
        bak_path(path)
    };
    load(&file).map(|(board, _)| board)
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use super::*;
    use crate::{BoardStore, Command, Origin, TaskDraft};

    fn add_task(store: &BoardStore) {
        store
            .apply(
                Origin::User,
                Command::CreateTask {
                    column: None,
                    position: None,
                    draft: TaskDraft {
                        description: "t".into(),
                        ..Default::default()
                    },
                },
                None,
            )
            .unwrap();
    }

    type Now = Arc<Mutex<DateTime<Local>>>;

    /// A store saved in a fresh dir, with a clock the test moves.
    fn setup() -> (tempfile::TempDir, PathBuf, Arc<BoardStore>, Now) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("board.json");
        let now: Now = Arc::new(Mutex::new(
            Local.with_ymd_and_hms(2026, 1, 1, 12, 0, 0).unwrap(),
        ));
        let store = BoardStore::new(true);
        let clock = now.clone();
        store.set_clock(move || *clock.lock().unwrap());
        store.save_as(&path).unwrap();
        (dir, path, store, now)
    }

    fn advance(now: &Now, minutes: i64) {
        *now.lock().unwrap() += Duration::minutes(minutes);
    }

    fn snapshots(path: &Path) -> Vec<String> {
        let mut v: Vec<_> = list(path)
            .into_iter()
            .map(|b| b.name)
            .filter(|n| n.starts_with("board-"))
            .collect();
        v.sort();
        v
    }

    #[test]
    fn save_keeps_previous_file_as_bak() {
        let (_d, path, store, _) = setup();
        assert!(!bak_path(&path).exists(), "no .bak on the first save");
        let before = fs::read(&path).unwrap();
        add_task(&store);
        store.save(false).unwrap();
        assert_eq!(fs::read(bak_path(&path)).unwrap(), before);
        assert_ne!(fs::read(&path).unwrap(), before);
    }

    #[test]
    fn snapshots_are_spaced_and_first_save_always_takes_one() {
        let (_d, path, store, now) = setup();
        add_task(&store);
        store.save(false).unwrap();
        assert_eq!(snapshots(&path), ["board-20260101-120000.json"]);
        advance(&now, 9);
        add_task(&store);
        store.save(false).unwrap();
        assert_eq!(snapshots(&path).len(), 1, "within 10 minutes");
        advance(&now, 2);
        add_task(&store);
        store.save(false).unwrap();
        assert_eq!(snapshots(&path).len(), 2);
        // Reopening makes the next save snapshot again.
        store.open(&path).unwrap();
        advance(&now, 1);
        store.save(true).unwrap();
        assert_eq!(snapshots(&path).len(), 3);
    }

    #[test]
    fn the_21st_snapshot_prunes_the_oldest() {
        let (_d, path, store, now) = setup();
        for _ in 0..21 {
            advance(&now, 11);
            add_task(&store);
            store.save(false).unwrap();
        }
        let names = snapshots(&path);
        assert_eq!(names.len(), MAX_SNAPSHOTS);
        assert!(!names.contains(&"board-20260101-121100.json".to_string()));
        assert_eq!(names[0], "board-20260101-122200.json");
    }

    #[test]
    fn a_failing_backup_does_not_fail_the_save_and_is_reported_once() {
        let (_d, path, store, now) = setup();
        // A file where the backups folder should go.
        fs::write(dir_of(&path), b"in the way").unwrap();
        add_task(&store);
        store.save(false).unwrap();
        let notice = store.take_backup_notice().expect("reported");
        assert!(notice.contains("backup"), "{notice}");
        assert!(store.take_backup_notice().is_none());
        advance(&now, 11);
        add_task(&store);
        store.save(false).unwrap();
        assert!(store.take_backup_notice().is_none(), "only one message");
        assert_eq!(load(&path).unwrap().0.columns[0].tasks.len(), 2);
    }

    #[test]
    fn restore_replaces_the_board_unsaved_and_clears_history() {
        let (_d, path, store, now) = setup();
        add_task(&store);
        store.save(false).unwrap(); // .bak holds the empty board
        advance(&now, 11);
        add_task(&store);
        store.save(false).unwrap(); // .bak holds one task
        advance(&now, 1);
        add_task(&store);
        assert!(store.history_labels().0.is_some());
        let on_disk = fs::read(&path).unwrap();

        let listed = store.list_backups();
        let snaps: Vec<_> = listed
            .iter()
            .filter(|b| b.name != "board.json.bak")
            .collect();
        assert!(listed.iter().any(|b| b.name == "board.json.bak"));
        assert_eq!(snaps[0].name, "board-20260101-121100.json", "newest first");
        assert_eq!(snaps[0].tasks, Some(1));

        store.restore_backup("board.json.bak").unwrap();
        let snap = store.snapshot();
        let count: usize = snap.board.columns.iter().map(|c| c.tasks.len()).sum();
        assert_eq!(count, 1);
        assert!(snap.dirty);
        assert_eq!(store.history_labels(), (None, None));
        // The replaced file was snapshotted, byte for byte.
        let kept = store
            .list_backups()
            .into_iter()
            .filter(|b| b.name != "board.json.bak")
            .any(|b| fs::read(dir_of(&path).join(&b.name)).unwrap() == on_disk);
        assert!(kept);
        // Saving afterwards is not refused as "modified on disk".
        store.save(false).unwrap();
    }

    #[test]
    fn unreadable_backups_are_listed_and_refuse_to_restore() {
        let (_d, path, store, _) = setup();
        fs::write(bak_path(&path), b"not json").unwrap();
        let listed = store.list_backups();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].tasks, None);
        assert!(store.restore_backup("board.json.bak").is_err());
        assert!(store.restore_backup("../board.json").is_err());
        assert!(!store.snapshot().dirty);
    }
}
