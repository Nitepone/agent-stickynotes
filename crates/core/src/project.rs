//! Project directories: a folder holding `stickynotes.json` and an
//! `artifacts/` folder for the files agents attach to tasks.

use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::error::{Error, Result};

pub const BOARD_FILE: &str = "stickynotes.json";
pub const ARTIFACTS_DIR: &str = "artifacts";

pub fn board_path(dir: &Path) -> PathBuf {
    dir.join(BOARD_FILE)
}

pub fn artifacts_dir(dir: &Path) -> PathBuf {
    dir.join(ARTIFACTS_DIR)
}

pub fn is_project(dir: &Path) -> bool {
    board_path(dir).is_file()
}

/// Create `dir` and its `artifacts/` folder if they are missing.
pub fn ensure_dirs(dir: &Path) -> Result<()> {
    let artifacts = artifacts_dir(dir);
    fs::create_dir_all(&artifacts).map_err(|source| Error::Io {
        path: artifacts,
        source,
    })
}

/// True if `dir` does not exist or has nothing in it.
pub fn is_empty_dir(dir: &Path) -> bool {
    match fs::read_dir(dir) {
        Ok(mut entries) => entries.next().is_none(),
        Err(_) => !dir.exists(),
    }
}

/// A folder name for a project called `name`: letters, digits, `-` and `_`,
/// with runs of anything else collapsed to one `-`. Never empty.
pub fn slug(name: &str) -> String {
    let mut out = String::new();
    for c in name.trim().chars() {
        if c.is_alphanumeric() || c == '_' {
            out.push(c);
        } else if !out.is_empty() && !out.ends_with('-') {
            out.push('-');
        }
    }
    let out = out.trim_end_matches('-');
    if out.is_empty() {
        "project".into()
    } else {
        out.into()
    }
}

/// A directory under `root` for a new project called `name` that does not
/// exist yet: `slug`, else `slug-2`, `slug-3`, ...
pub fn new_project_dir(root: &Path, name: &str) -> PathBuf {
    let base = slug(name);
    let mut candidate = root.join(&base);
    let mut n = 2;
    while candidate.exists() {
        candidate = root.join(format!("{base}-{n}"));
        n += 1;
    }
    candidate
}

/// A project found under a projects folder.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectEntry {
    pub dir: PathBuf,
    /// The board's title.
    pub title: String,
}

/// The projects directly under `root`, sorted by title. Folders without a
/// readable `stickynotes.json` are skipped.
pub fn list_projects(root: &Path) -> Vec<ProjectEntry> {
    #[derive(Deserialize)]
    struct Head {
        #[serde(default)]
        title: String,
    }
    let Ok(entries) = fs::read_dir(root) else {
        return Vec::new();
    };
    let mut found: Vec<ProjectEntry> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|dir| dir.is_dir())
        .filter_map(|dir| {
            let bytes = fs::read(board_path(&dir)).ok()?;
            let head: Head = serde_json::from_slice(&bytes).ok()?;
            let title = if head.title.is_empty() {
                dir.file_name()?.to_string_lossy().into_owned()
            } else {
                head.title
            };
            Some(ProjectEntry { dir, title })
        })
        .collect();
    found.sort_by_key(|p| p.title.to_lowercase());
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slugs_are_safe_folder_names() {
        assert_eq!(slug("Sprint 4"), "Sprint-4");
        assert_eq!(slug("  ../etc/passwd "), "etc-passwd");
        assert_eq!(slug("a  --  b"), "a-b");
        assert_eq!(slug("!!!"), "project");
        assert_eq!(slug("Café_1"), "Café_1");
    }

    #[test]
    fn new_project_dirs_do_not_collide() {
        let root = tempfile::tempdir().unwrap();
        let first = new_project_dir(root.path(), "Demo");
        fs::create_dir(&first).unwrap();
        assert_eq!(
            new_project_dir(root.path(), "Demo"),
            root.path().join("Demo-2")
        );
    }

    #[test]
    fn lists_only_project_folders_sorted_by_title() {
        let root = tempfile::tempdir().unwrap();
        for (folder, json) in [
            ("b", r#"{"title":"Beta"}"#),
            ("a", r#"{"title":"alpha"}"#),
            ("untitled", r#"{}"#),
            ("broken", "not json"),
        ] {
            fs::create_dir(root.path().join(folder)).unwrap();
            fs::write(root.path().join(folder).join(BOARD_FILE), json).unwrap();
        }
        fs::create_dir(root.path().join("not-a-project")).unwrap();
        fs::write(root.path().join("stray.json"), "{}").unwrap();

        let titles: Vec<_> = list_projects(root.path())
            .into_iter()
            .map(|p| p.title)
            .collect();
        assert_eq!(titles, ["alpha", "Beta", "untitled"]);
        assert!(list_projects(&root.path().join("missing")).is_empty());
    }
}
