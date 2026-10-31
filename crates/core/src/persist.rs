//! JSON load/save with atomic writes.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::SystemTime;

use crate::error::{Error, Result};
use crate::model::{Board, SCHEMA_VERSION};

/// Identifies the version of a file on disk, to detect outside modification.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FileStamp {
    modified: SystemTime,
    len: u64,
}

impl FileStamp {
    pub fn of(path: &Path) -> Option<FileStamp> {
        let meta = fs::metadata(path).ok()?;
        Some(FileStamp {
            modified: meta.modified().ok()?,
            len: meta.len(),
        })
    }
}

pub fn load(path: &Path) -> Result<(Board, Option<FileStamp>)> {
    let bytes = fs::read(path).map_err(|e| io_err(path, e))?;
    let board: Board = serde_json::from_slice(&bytes).map_err(|source| Error::Json {
        path: path.to_path_buf(),
        source,
    })?;
    if board.schema_version > SCHEMA_VERSION {
        return Err(Error::UnsupportedSchema(board.schema_version));
    }
    Ok((board, FileStamp::of(path)))
}

pub fn save(path: &Path, board: &Board) -> Result<Option<FileStamp>> {
    let mut json = serde_json::to_vec_pretty(board).expect("board serializes");
    json.push(b'\n');
    write_atomic(path, &json)?;
    Ok(FileStamp::of(path))
}

/// Write to a uniquely named temp file in the same directory, fsync, rename
/// over `path`, then (on Unix) fsync the directory so the rename is durable.
/// The temp file is created with `create_new`, so it never follows a symlink
/// or reuses another writer's file.
pub fn write_atomic(path: &Path, contents: &[u8]) -> Result<()> {
    let (tmp, mut f) = create_temp(path).map_err(|e| io_err(path, e))?;
    let result = (|| {
        f.write_all(contents)?;
        f.sync_all()?;
        drop(f);
        fs::rename(&tmp, path)?;
        sync_parent(path);
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result.map_err(|e| io_err(path, e))
}

fn create_temp(path: &Path) -> std::io::Result<(PathBuf, fs::File)> {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let mut last = None;
    for _ in 0..100 {
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let tmp = path.with_file_name(format!(".{name}.tmp-{}-{n}", std::process::id()));
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&tmp)
        {
            Ok(f) => return Ok((tmp, f)),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => last = Some(e),
            Err(e) => return Err(e),
        }
    }
    Err(last.unwrap())
}

#[cfg(unix)]
fn sync_parent(path: &Path) {
    let dir = match path.parent() {
        Some(d) if !d.as_os_str().is_empty() => d,
        _ => Path::new("."),
    };
    if let Ok(d) = fs::File::open(dir) {
        let _ = d.sync_all();
    }
}

#[cfg(not(unix))]
fn sync_parent(_path: &Path) {}

fn io_err(path: &Path, source: std::io::Error) -> Error {
    Error::Io {
        path: path.to_path_buf(),
        source,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_preserves_unknown_fields() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("board.json");
        let mut board = Board::new_default();
        board
            .extra
            .insert("future_field".into(), serde_json::json!({"a": 1}));
        board.columns[0]
            .extra
            .insert("color".into(), serde_json::json!("red"));
        save(&path, &board).unwrap();

        let (loaded, stamp) = load(&path).unwrap();
        assert_eq!(loaded, board);
        assert!(stamp.is_some());

        let text = fs::read_to_string(&path).unwrap();
        assert!(text.contains("future_field"));
        assert!(text.contains("\"color\": \"red\""));
    }

    #[test]
    fn rejects_newer_schema() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("board.json");
        let mut board = Board::new_default();
        board.schema_version = SCHEMA_VERSION + 1;
        save(&path, &board).unwrap();
        assert!(matches!(load(&path), Err(Error::UnsupportedSchema(_))));
    }

    #[test]
    fn atomic_write_leaves_no_temp_file() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("b.json");
        write_atomic(&path, b"one").unwrap();
        write_atomic(&path, b"two").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"two");
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
    }

    #[test]
    fn concurrent_writes_leave_one_complete_file() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("t.json");
        let handles: Vec<_> = (0..8)
            .map(|i| {
                let path = path.clone();
                std::thread::spawn(move || {
                    let body = format!("{i}").repeat(10_000);
                    for _ in 0..20 {
                        write_atomic(&path, body.as_bytes()).unwrap();
                    }
                })
            })
            .collect();
        for h in handles {
            h.join().unwrap();
        }
        let data = fs::read_to_string(&path).unwrap();
        assert_eq!(data.len(), 10_000);
        assert!(data.chars().all(|c| c == data.chars().next().unwrap()));
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
    }

    #[test]
    fn failed_write_keeps_old_file_and_leaves_no_temp() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("t.json");
        write_atomic(&path, b"old").unwrap();
        // Renaming a file over a directory fails.
        let target = dir.path().join("sub");
        fs::create_dir(&target).unwrap();
        assert!(write_atomic(&target, b"new").is_err());
        assert_eq!(fs::read(&path).unwrap(), b"old");
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 2);
    }
}
