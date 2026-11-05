//! Files attached to tasks: which names and contents are accepted, and how
//! they are written to and read from a project's `artifacts/` folder.
//!
//! Artifacts are Markdown, images and PDFs. Names are reduced to a safe file name
//! (no folders), contents are checked against their type, and a file that
//! already exists is never overwritten.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::error::{Error, Result};
use crate::model::ArtifactKind;
use crate::project;

/// Largest Markdown or SVG file.
pub const MAX_TEXT_BYTES: usize = 1 << 20;
/// Largest raster image.
pub const MAX_IMAGE_BYTES: usize = 5 << 20;
/// Largest PDF.
pub const MAX_PDF_BYTES: usize = 10 << 20;
/// Most artifacts one task can have.
pub const MAX_PER_TASK: usize = 50;

/// File extensions that are accepted, and what they are.
const TYPES: &[(&str, ArtifactKind)] = &[
    ("md", ArtifactKind::Markdown),
    ("png", ArtifactKind::Image),
    ("jpg", ArtifactKind::Image),
    ("jpeg", ArtifactKind::Image),
    ("gif", ArtifactKind::Image),
    ("webp", ArtifactKind::Image),
    ("svg", ArtifactKind::Image),
    ("pdf", ArtifactKind::Pdf),
];

fn invalid(msg: impl Into<String>) -> Error {
    Error::Validation(msg.into())
}

/// The kind a file name's extension stands for, if it is an accepted one.
pub fn kind_of(file_name: &str) -> Option<ArtifactKind> {
    let ext = file_name.rsplit_once('.')?.1.to_ascii_lowercase();
    TYPES.iter().find(|(e, _)| *e == ext).map(|(_, k)| *k)
}

/// Turn a requested name into a plain file name such as `login-flow.png`:
/// any folders are dropped, the stem is reduced to letters, digits, `-` and
/// `_`, and the extension must be an accepted one.
pub fn clean_name(requested: &str) -> Result<(String, ArtifactKind)> {
    let base = requested
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or_default()
        .trim();
    let (stem, ext) = base.rsplit_once('.').ok_or_else(|| {
        invalid(format!(
            "'{requested}' needs a file extension: {}",
            accepted_list()
        ))
    })?;
    let ext = ext.to_ascii_lowercase();
    let kind = kind_of(&format!("x.{ext}")).ok_or_else(|| {
        invalid(format!(
            "'.{ext}' files are not accepted; use {}",
            accepted_list()
        ))
    })?;
    Ok((format!("{}.{ext}", project::slug(stem)), kind))
}

fn accepted_list() -> String {
    TYPES
        .iter()
        .map(|(e, _)| format!(".{e}"))
        .collect::<Vec<_>>()
        .join(", ")
}

fn extension(file_name: &str) -> String {
    file_name
        .rsplit_once('.')
        .map(|(_, e)| e.to_ascii_lowercase())
        .unwrap_or_default()
}

/// Whether the file is text (Markdown or SVG) rather than binary.
pub fn is_text(file_name: &str, kind: ArtifactKind) -> bool {
    kind == ArtifactKind::Markdown || (kind == ArtifactKind::Image && extension(file_name) == "svg")
}

/// The size limit for a file of this name and kind.
pub fn max_bytes(file_name: &str, kind: ArtifactKind) -> usize {
    match kind {
        _ if is_text(file_name, kind) => MAX_TEXT_BYTES,
        ArtifactKind::Pdf => MAX_PDF_BYTES,
        _ => MAX_IMAGE_BYTES,
    }
}

/// Check that `data` is plausibly what `file_name`'s extension says.
pub fn validate_content(file_name: &str, kind: ArtifactKind, data: &[u8]) -> Result<()> {
    let ext = extension(file_name);
    let is_text = is_text(file_name, kind);
    let limit = max_bytes(file_name, kind);
    if data.is_empty() {
        return Err(invalid("the artifact is empty"));
    }
    if data.len() > limit {
        return Err(invalid(format!(
            "'{file_name}' is {} KiB; the limit for this type is {} KiB",
            data.len().div_ceil(1024),
            limit / 1024
        )));
    }
    if is_text {
        let text = std::str::from_utf8(data)
            .map_err(|_| invalid(format!("'{file_name}' is not valid UTF-8 text")))?;
        if ext == "svg" && !text.contains("<svg") {
            return Err(invalid(format!("'{file_name}' is not an SVG image")));
        }
        return Ok(());
    }
    if kind == ArtifactKind::Pdf {
        return if data.starts_with(b"%PDF-") {
            Ok(())
        } else {
            Err(invalid(format!(
                "the contents of '{file_name}' are not a PDF"
            )))
        };
    }
    let looks_right = match ext.as_str() {
        "png" => data.starts_with(b"\x89PNG\r\n\x1a\n"),
        "jpg" | "jpeg" => data.starts_with(&[0xFF, 0xD8, 0xFF]),
        "gif" => data.starts_with(b"GIF87a") || data.starts_with(b"GIF89a"),
        "webp" => data.len() > 12 && &data[..4] == b"RIFF" && &data[8..12] == b"WEBP",
        _ => false,
    };
    if looks_right {
        Ok(())
    } else {
        Err(invalid(format!(
            "the contents of '{file_name}' are not a .{ext} image"
        )))
    }
}

/// Write `data` as a new file in `dir`'s `artifacts/` folder, named
/// `file_name` or, if that is taken, `stem-2.ext`, `stem-3.ext`, ... Returns
/// the name used. An existing file is never replaced.
pub fn write_new(project_dir: &Path, file_name: &str, data: &[u8]) -> Result<String> {
    let folder = project::artifacts_dir(project_dir);
    project::ensure_dirs(project_dir)?;
    let (stem, ext) = file_name.rsplit_once('.').unwrap_or((file_name, ""));
    for n in 1.. {
        let name = if n == 1 {
            file_name.to_string()
        } else {
            format!("{stem}-{n}.{ext}")
        };
        let path = folder.join(&name);
        // `create_new` fails if anything is there, including a symlink.
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
        {
            Ok(mut file) => {
                let written = file.write_all(data).and_then(|_| file.sync_all());
                if let Err(source) = written {
                    drop(file);
                    let _ = fs::remove_file(&path);
                    return Err(Error::Io { path, source });
                }
                return Ok(name);
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(source) => return Err(Error::Io { path, source }),
        }
    }
    unreachable!("the loop only ends by returning")
}

pub fn remove(project_dir: &Path, file_name: &str) {
    if is_plain_name(file_name) {
        let _ = fs::remove_file(project::artifacts_dir(project_dir).join(file_name));
    }
}

/// A single file name with no folders in it.
fn is_plain_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with('.')
        && name
            .chars()
            .all(|c| c.is_alphanumeric() || matches!(c, '-' | '_' | '.'))
}

/// The path of an artifact's file. Only plain file names that are regular
/// files in `artifacts/` are found; symlinks are not followed out of the folder.
pub fn locate(project_dir: &Path, file_name: &str) -> Result<PathBuf> {
    if !is_plain_name(file_name) {
        return Err(invalid(format!(
            "'{file_name}' is not an artifact file name"
        )));
    }
    let path = project::artifacts_dir(project_dir).join(file_name);
    match fs::symlink_metadata(&path) {
        Ok(meta) if meta.is_file() => Ok(path),
        _ => Err(Error::not_found("artifact file", file_name)),
    }
}

pub fn read(project_dir: &Path, file_name: &str) -> Result<Vec<u8>> {
    let path = locate(project_dir, file_name)?;
    fs::read(&path).map_err(|source| Error::Io { path, source })
}

/// A file found in `artifacts/`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StoredFile {
    pub name: String,
    pub kind: ArtifactKind,
    pub size: u64,
    /// When the file was last written (ms since the epoch); 0 if unknown.
    pub modified_ms: i64,
}

/// The accepted files in `artifacts/`, sorted by name.
pub fn list_files(project_dir: &Path) -> Vec<StoredFile> {
    let Ok(entries) = fs::read_dir(project::artifacts_dir(project_dir)) else {
        return Vec::new();
    };
    let mut files: Vec<StoredFile> = entries
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            let meta = fs::symlink_metadata(e.path()).ok()?;
            let name = e.file_name().to_string_lossy().into_owned();
            if !meta.is_file() || !is_plain_name(&name) {
                return None;
            }
            Some(StoredFile {
                kind: kind_of(&name)?,
                name,
                size: meta.len(),
                modified_ms: meta
                    .modified()
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map_or(0, |d| d.as_millis() as i64),
            })
        })
        .collect();
    files.sort_by(|a, b| a.name.cmp(&b.name));
    files
}

#[cfg(test)]
mod tests {
    use super::*;

    const PNG: &[u8] = b"\x89PNG\r\n\x1a\nrest";

    #[test]
    fn names_are_reduced_to_plain_files() {
        let clean = |n: &str| clean_name(n).map(|(name, _)| name);
        assert_eq!(clean("Login Flow.PNG").unwrap(), "Login-Flow.png");
        assert_eq!(clean("../../etc/passwd.md").unwrap(), "passwd.md");
        assert_eq!(clean("C:\\x\\notes.md").unwrap(), "notes.md");
        assert_eq!(clean("design.v2.md").unwrap(), "design-v2.md");
        assert!(clean("notes").is_err());
        assert!(clean("run.sh").is_err());
        assert!(clean(".md").is_ok_and(|n| n == "project.md"));
        assert_eq!(clean_name("a.svg").unwrap().1, ArtifactKind::Image);
    }

    #[test]
    fn contents_must_match_the_type() {
        let md = ArtifactKind::Markdown;
        let img = ArtifactKind::Image;
        assert!(validate_content("a.md", md, b"# hi").is_ok());
        assert!(validate_content("a.md", md, &[0xff, 0xfe, 0x00]).is_err());
        assert!(validate_content("a.md", md, b"").is_err());
        assert!(validate_content("a.png", img, PNG).is_ok());
        assert!(validate_content("a.png", img, b"<html>").is_err());
        assert!(validate_content("a.jpg", img, &[0xFF, 0xD8, 0xFF, 0xE0]).is_ok());
        assert!(validate_content("a.gif", img, b"GIF89a..").is_ok());
        assert!(validate_content("a.webp", img, b"RIFF\0\0\0\0WEBPVP8 ").is_ok());
        assert!(validate_content("a.svg", img, b"<svg xmlns=''/>").is_ok());
        assert!(validate_content("a.svg", img, b"<html/>").is_err());
    }

    #[test]
    fn pdfs_are_accepted_by_their_header() {
        let pdf = ArtifactKind::Pdf;
        assert_eq!(
            clean_name("Spec Sheet.PDF").unwrap(),
            ("Spec-Sheet.pdf".into(), pdf)
        );
        assert!(validate_content("a.pdf", pdf, b"%PDF-1.7\n%...").is_ok());
        let wrong = validate_content("a.pdf", pdf, PNG).unwrap_err().to_string();
        assert!(
            wrong.contains("a.pdf") && wrong.contains("not a PDF"),
            "{wrong}"
        );
        assert!(validate_content("a.pdf", pdf, b"").is_err());
    }

    #[test]
    fn size_limits_apply_per_type() {
        let big_text = vec![b'a'; MAX_TEXT_BYTES + 1];
        assert!(validate_content("a.md", ArtifactKind::Markdown, &big_text).is_err());
        let mut big_png = PNG.to_vec();
        big_png.resize(MAX_TEXT_BYTES + 1, 0);
        assert!(validate_content("a.png", ArtifactKind::Image, &big_png).is_ok());
        big_png.resize(MAX_IMAGE_BYTES + 1, 0);
        assert!(validate_content("a.png", ArtifactKind::Image, &big_png).is_err());
        let mut big_pdf = b"%PDF-1.7".to_vec();
        big_pdf.resize(MAX_PDF_BYTES, 0);
        assert!(validate_content("a.pdf", ArtifactKind::Pdf, &big_pdf).is_ok());
        big_pdf.push(0);
        assert!(validate_content("a.pdf", ArtifactKind::Pdf, &big_pdf).is_err());
        assert_eq!(max_bytes("a.svg", ArtifactKind::Image), MAX_TEXT_BYTES);
        assert_eq!(max_bytes("a.png", ArtifactKind::Image), MAX_IMAGE_BYTES);
    }

    #[test]
    fn existing_files_are_never_overwritten() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(write_new(dir.path(), "a.md", b"one").unwrap(), "a.md");
        assert_eq!(write_new(dir.path(), "a.md", b"two").unwrap(), "a-2.md");
        assert_eq!(read(dir.path(), "a.md").unwrap(), b"one");
        assert_eq!(read(dir.path(), "a-2.md").unwrap(), b"two");
    }

    #[test]
    fn reads_stay_inside_the_folder() {
        let dir = tempfile::tempdir().unwrap();
        write_new(dir.path(), "a.md", b"one").unwrap();
        fs::write(dir.path().join("secret.md"), "secret").unwrap();
        assert!(read(dir.path(), "../secret.md").is_err());
        assert!(read(dir.path(), "missing.md").is_err());
        #[cfg(unix)]
        {
            let link = project::artifacts_dir(dir.path()).join("link.md");
            std::os::unix::fs::symlink(dir.path().join("secret.md"), &link).unwrap();
            assert!(read(dir.path(), "link.md").is_err());
            let names: Vec<_> = list_files(dir.path()).into_iter().map(|f| f.name).collect();
            assert_eq!(names, ["a.md"]);
        }
    }

    #[test]
    fn lists_accepted_files_only() {
        let dir = tempfile::tempdir().unwrap();
        write_new(dir.path(), "b.png", PNG).unwrap();
        write_new(dir.path(), "a.md", b"x").unwrap();
        fs::write(project::artifacts_dir(dir.path()).join("run.sh"), "x").unwrap();
        let found = list_files(dir.path());
        assert_eq!(
            found.iter().map(|f| f.name.as_str()).collect::<Vec<_>>(),
            ["a.md", "b.png"]
        );
        assert_eq!(found[1].kind, ArtifactKind::Image);
    }
}
