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
    /// Project reopened on launch when none is given on the command line.
    pub last_project: Option<PathBuf>,
    /// Executable used to draft requirements and criteria (Claude Code).
    pub claude_command: String,
    /// `"light"` or `"dark"`.
    pub theme_mode: String,
    /// Custom accent colors as `#rrggbb`; empty means the theme's default.
    pub primary_color: String,
    pub secondary_color: String,
    /// `"system"`, `"on"` or `"off"`: whether to replace animations with
    /// static effects.
    pub reduce_motion: String,
    /// When the user last used the app (milliseconds since the Unix epoch).
    /// Notes an agent changed after this glow until the user is back.
    pub last_interaction_ms: i64,
    /// Sticky note color as `#rrggbb`; empty means the theme's yellow.
    pub note_color: String,
    /// Underline misspelled words in the task editor.
    pub spell_check: bool,
    /// Which backend drafts requirements and criteria (see `editor::AGENTS`).
    pub draft_agent: String,
    /// Added to the built-in prompt of the draft agent.
    pub draft_system_prompt: String,
    /// Claude Code model alias; empty means Claude Code's own default.
    pub draft_model: String,
    /// Claude Code thinking (effort) level; empty means its default.
    pub draft_effort: String,
    /// Display style of the Markdown viewer (`default`, `reading`, ...); the
    /// viewer falls back to the default for an id it does not know.
    pub markdown_style: String,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            agent_write: false,
            port: DEFAULT_PORT,
            last_project: None,
            claude_command: "claude".into(),
            theme_mode: crate::theme::LIGHT.into(),
            primary_color: String::new(),
            secondary_color: String::new(),
            reduce_motion: crate::motion::SYSTEM.into(),
            last_interaction_ms: 0,
            note_color: String::new(),
            spell_check: true,
            draft_agent: crate::editor::CLAUDE_CODE.into(),
            draft_system_prompt: String::new(),
            draft_model: String::new(),
            draft_effort: String::new(),
            markdown_style: "default".into(),
        }
    }
}

pub struct Config {
    dir: PathBuf,
    /// Where new projects are created and listed by default.
    projects_dir: PathBuf,
}

impl Config {
    pub fn new() -> Result<Self> {
        let dirs = directories::ProjectDirs::from("", "", "agent-stickynotes")
            .context("cannot determine the config directory")?;
        Ok(Config {
            dir: dirs.config_dir().to_path_buf(),
            projects_dir: dirs.data_dir().join("projects"),
        })
    }

    pub fn projects_dir(&self) -> &Path {
        &self.projects_dir
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

#[cfg(test)]
mod tests {
    use super::*;

    fn config_in(dir: &Path) -> Config {
        Config {
            dir: dir.to_path_buf(),
            projects_dir: dir.join("projects"),
        }
    }

    #[test]
    fn first_launch_uses_the_default_theme() {
        let dir = tempfile::tempdir().unwrap();
        let settings = config_in(dir.path()).load_settings();
        assert_eq!(settings.theme_mode, "light");
        assert_eq!(settings.primary_color, "");
        assert_eq!(settings.secondary_color, "");
    }

    #[test]
    fn settings_from_before_projects_still_load() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("settings.json"),
            r#"{"agent_write": true, "last_file": "/tmp/board.json"}"#,
        )
        .unwrap();
        let settings = config_in(dir.path()).load_settings();
        assert!(settings.agent_write);
        assert_eq!(settings.last_project, None);
    }

    #[test]
    fn settings_files_from_before_themes_still_load() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("settings.json"),
            r#"{"agent_write": true, "port": 7317}"#,
        )
        .unwrap();
        let settings = config_in(dir.path()).load_settings();
        assert!(settings.agent_write);
        assert_eq!(settings.theme_mode, "light");
    }

    #[test]
    fn theme_choices_survive_a_restart() {
        let dir = tempfile::tempdir().unwrap();
        let config = config_in(dir.path());
        let mut settings = config.load_settings();
        settings.theme_mode = "dark".into();
        settings.primary_color = "#ff8800".into();
        settings.secondary_color = "#00aa99".into();
        config.save_settings(&settings).unwrap();

        let restored = config_in(dir.path()).load_settings();
        assert_eq!(restored.theme_mode, "dark");
        assert_eq!(restored.primary_color, "#ff8800");
        assert_eq!(restored.secondary_color, "#00aa99");
    }

    #[test]
    fn motion_and_interaction_defaults_and_persistence() {
        let dir = tempfile::tempdir().unwrap();
        let config = config_in(dir.path());
        let mut settings = config.load_settings();
        assert_eq!(settings.reduce_motion, "system");
        assert_eq!(settings.last_interaction_ms, 0);
        settings.reduce_motion = "on".into();
        settings.last_interaction_ms = 1_761_800_000_123;
        config.save_settings(&settings).unwrap();
        let restored = config_in(dir.path()).load_settings();
        assert_eq!(restored.reduce_motion, "on");
        assert_eq!(restored.last_interaction_ms, 1_761_800_000_123);
    }

    #[test]
    fn settings_files_from_before_editor_preferences_still_load() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("settings.json"),
            r##"{"agent_write": true, "theme_mode": "dark", "primary_color": "#ff8800"}"##,
        )
        .unwrap();
        let settings = config_in(dir.path()).load_settings();
        assert!(settings.agent_write);
        assert_eq!(settings.primary_color, "#ff8800");
        assert_eq!(settings.note_color, "");
        assert!(settings.spell_check, "spell check is on unless turned off");
        assert_eq!(settings.draft_agent, "claude_code");
        assert_eq!(settings.draft_system_prompt, "");
        assert_eq!(settings.draft_model, "");
        assert_eq!(settings.draft_effort, "");
        assert_eq!(settings.markdown_style, "default");
    }

    #[test]
    fn editor_and_note_choices_survive_a_restart() {
        let dir = tempfile::tempdir().unwrap();
        let config = config_in(dir.path());
        let mut settings = config.load_settings();
        settings.note_color = "#bfe3ff".into();
        settings.spell_check = false;
        settings.draft_system_prompt = "Write in British English.".into();
        settings.draft_model = "opus".into();
        settings.draft_effort = "high".into();
        settings.markdown_style = "reading".into();
        config.save_settings(&settings).unwrap();

        let restored = config_in(dir.path()).load_settings();
        assert_eq!(restored.note_color, "#bfe3ff");
        assert!(!restored.spell_check);
        assert_eq!(restored.draft_system_prompt, "Write in British English.");
        assert_eq!(restored.draft_model, "opus");
        assert_eq!(restored.draft_effort, "high");
        assert_eq!(restored.markdown_style, "reading");
    }

    #[test]
    fn a_corrupt_settings_file_falls_back_to_defaults() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("settings.json"), "{ not json").unwrap();
        assert_eq!(config_in(dir.path()).load_settings().theme_mode, "light");
    }
}
