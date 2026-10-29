//! Per-user app settings and the agent API token, stored under the XDG
//! config directory (`~/.config/agent-stickynotes/`).

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

pub const DEFAULT_PORT: u16 = 7317;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// Whether agents may modify the board. Off until the user opts in.
    pub agent_write: bool,
    pub port: u16,
    /// Board reopened on launch when no file is given on the command line.
    pub last_file: Option<PathBuf>,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            agent_write: false,
            port: DEFAULT_PORT,
            last_file: None,
        }
    }
}

pub struct Config {
    dir: PathBuf,
}

impl Config {
    pub fn new() -> Result<Self> {
        let dirs = directories::ProjectDirs::from("", "", "agent-stickynotes")
            .context("cannot determine the config directory")?;
        Ok(Config {
            dir: dirs.config_dir().to_path_buf(),
        })
    }

    pub fn load_settings(&self) -> Settings {
        fs::read(self.dir.join("settings.json"))
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default()
    }

    pub fn save_settings(&self, settings: &Settings) -> Result<()> {
        fs::create_dir_all(&self.dir)?;
        let json = serde_json::to_vec_pretty(settings)?;
        stickynotes_core::persist::write_atomic(&self.dir.join("settings.json"), &json)?;
        Ok(())
    }

    /// The bearer token agents must present, created on first use (mode 0600).
    pub fn token(&self) -> Result<String> {
        let path = self.dir.join("token");
        if let Ok(token) = fs::read_to_string(&path) {
            let token = token.trim().to_string();
            if !token.is_empty() {
                return Ok(token);
            }
        }
        fs::create_dir_all(&self.dir)?;
        let token = format!(
            "{}{}",
            uuid::Uuid::new_v4().simple(),
            uuid::Uuid::new_v4().simple()
        );
        write_private(&path, &token)?;
        Ok(token)
    }
}

#[cfg(unix)]
fn write_private(path: &Path, contents: &str) -> Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
        .with_context(|| format!("writing {}", path.display()))?;
    f.write_all(contents.as_bytes())?;
    Ok(())
}

#[cfg(not(unix))]
fn write_private(path: &Path, contents: &str) -> Result<()> {
    fs::write(path, contents).with_context(|| format!("writing {}", path.display()))
}
