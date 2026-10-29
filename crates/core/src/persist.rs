//! JSON load/save with atomic writes.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
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

/// Write to a temp file in the same directory, fsync, then rename over `path`.
pub fn write_atomic(path: &Path, contents: &[u8]) -> Result<()> {
    let tmp = temp_path(path);
    let result = (|| {
        let mut f = fs::File::create(&tmp)?;
        f.write_all(contents)?;
        f.sync_all()?;
        fs::rename(&tmp, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result.map_err(|e| io_err(path, e))
}

fn temp_path(path: &Path) -> PathBuf {
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    path.with_file_name(format!(".{name}.tmp-{}", std::process::id()))
}

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
}
