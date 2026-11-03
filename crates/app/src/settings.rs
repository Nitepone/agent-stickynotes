//! Per-user app settings and the agent API token, stored under the XDG
//! config directory (`~/.config/agent-stickynotes/`).

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

pub const DEFAULT_PORT: u16 = 7317;
pub const MIN_UI_SCALE: f64 = 0.7;
pub const MAX_UI_SCALE: f64 = 2.0;

/// A scale clamped to the supported range and rounded to whole percent;
/// anything that is not a number is actual size.
pub fn normalize_ui_scale(scale: f64) -> f64 {
    if !scale.is_finite() {
        return 1.0;
    }
    (scale.clamp(MIN_UI_SCALE, MAX_UI_SCALE) * 100.0).round() / 100.0
}

/// A credential kept in the settings file. Its `Debug` output hides the value
/// so it cannot end up in a log by accident.
#[derive(Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Secret(pub String);

impl std::fmt::Debug for Secret {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(if self.0.is_empty() {
            "Secret(unset)"
        } else {
            "Secret(<hidden>)"
        })
    }
}

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
    /// `"user"` (one note color) or `"variable"` (a palette color per category).
    pub note_style: String,
    /// Id of the palette used by the variable style (see `theme::NOTE_PALETTES`).
    pub note_palette: String,
    /// Underline misspelled words in the task editor.
    pub spell_check: bool,
    /// Which backend drafts requirements and criteria (see `editor::AGENTS`).
    pub draft_agent: String,
    /// Added to the built-in prompt of the draft agent.
    pub draft_system_prompt: String,
    /// Claude Code model alias (empty means its own default), or the model
    /// name to ask an Ollama-style server for.
    pub draft_model: String,
    /// Claude Code thinking (effort) level; empty means its default.
    pub draft_effort: String,
    /// Base URL of the Ollama-style server used when `draft_agent` is `ollama`.
    pub ollama_endpoint: String,
    /// Optional bearer token for that server. Kept in this file in plain text
    /// and never printed (see [`Secret`]).
    pub ollama_token: Secret,
    /// Display style of the Markdown viewer (`default`, `reading`, ...); the
    /// viewer falls back to the default for an id it does not know.
    pub markdown_style: String,
    /// Interface scale: 1.0 is actual size (`MIN_UI_SCALE` to `MAX_UI_SCALE`).
    pub ui_scale: f64,
    /// Fields this version does not know, kept so a newer version's settings
    /// survive a load and save.
    #[serde(flatten, skip_serializing_if = "serde_json::Map::is_empty")]
    pub extra: serde_json::Map<String, serde_json::Value>,
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
            note_style: crate::theme::NOTE_STYLES[0].into(),
            note_palette: crate::theme::NOTE_PALETTES[0].into(),
            spell_check: true,
            draft_agent: crate::editor::CLAUDE_CODE.into(),
            draft_system_prompt: String::new(),
            draft_model: String::new(),
            draft_effort: String::new(),
            ollama_endpoint: crate::editor::DEFAULT_OLLAMA_ENDPOINT.into(),
            ollama_token: Secret::default(),
            markdown_style: "default".into(),
            ui_scale: 1.0,
            extra: serde_json::Map::new(),
        }
    }
}

impl Settings {
    /// Replace every preference that is not valid with its default, so the
    /// rest of the app can trust the values.
    pub fn sanitized(mut self) -> Self {
        self.theme_mode = crate::theme::normalize_mode(&self.theme_mode).into();
        self.reduce_motion = crate::motion::normalize_setting(&self.reduce_motion).into();
        self.draft_agent = crate::editor::normalize_agent(&self.draft_agent).into();
        self.note_style = crate::theme::normalize_note_style(&self.note_style).into();
        self.note_palette = crate::theme::normalize_note_palette(&self.note_palette).into();
        for c in [
            &mut self.primary_color,
            &mut self.secondary_color,
            &mut self.note_color,
        ] {
            *c = crate::theme::normalize_color(c).unwrap_or_default();
        }
        self.draft_model = if self.draft_agent == crate::editor::OLLAMA {
            crate::editor::model_name(&self.draft_model).unwrap_or_default()
        } else {
            // Claude Code only knows its aliases.
            crate::editor::model(&self.draft_model)
                .unwrap_or_default()
                .into()
        };
        self.ollama_endpoint = crate::editor::endpoint(&self.ollama_endpoint)
            .unwrap_or_else(|| crate::editor::DEFAULT_OLLAMA_ENDPOINT.into());
        self.ollama_token = Secret(crate::editor::token(&self.ollama_token.0).unwrap_or_default());
        self.draft_effort = crate::editor::effort(&self.draft_effort)
            .unwrap_or_default()
            .into();
        self.ui_scale = normalize_ui_scale(self.ui_scale);
        self
    }

    /// The preferences the UI shows, as JSON keyed like [`PREFS`], plus
    /// `reduce_motion`: whether animations are actually reduced, given what
    /// the desktop prefers.
    pub fn prefs_json(&self, system_reduced_motion: bool) -> String {
        serde_json::json!({
            "theme_mode": self.theme_mode,
            "primary_color": self.primary_color,
            "secondary_color": self.secondary_color,
            "note_color": self.note_color,
            "note_style": self.note_style,
            "note_palette": self.note_palette,
            "markdown_style": self.markdown_style,
            "ui_scale": self.ui_scale,
            "spell_check": self.spell_check,
            "draft_agent": self.draft_agent,
            "draft_system_prompt": self.draft_system_prompt,
            "draft_model": self.draft_model,
            "draft_effort": self.draft_effort,
            "ollama_endpoint": self.ollama_endpoint,
            // The token field of Preferences needs the value to show it (masked).
            "ollama_token": self.ollama_token.0,
            "motion_setting": self.reduce_motion,
            "reduce_motion": crate::motion::effective(&self.reduce_motion, system_reduced_motion),
        })
        .to_string()
    }
}

/// One user preference that can be changed with [`pref`]: `validate` turns
/// the text the UI sends into the value to store (`None` rejects it, and the
/// empty text is how a color is reset), `set` stores it.
pub struct Pref {
    pub key: &'static str,
    pub validate: fn(&str) -> Option<String>,
    pub set: fn(&mut Settings, String),
}

fn text(value: &str) -> Option<String> {
    Some(value.to_string())
}

/// A color, or empty for the theme's default.
fn color(value: &str) -> Option<String> {
    if value.trim().is_empty() {
        return Some(String::new());
    }
    crate::theme::normalize_color(value)
}

/// `normalized` only if `value` is exactly that choice (so unknown text is
/// not silently turned into the default).
fn exact(normalized: &str, value: &str) -> Option<String> {
    value
        .trim()
        .eq_ignore_ascii_case(normalized)
        .then(|| normalized.to_string())
}

/// Preferences changed by the UI. Keys are the `prefs_json` keys, except
/// that `motion_setting` is stored as the `reduce_motion` setting.
pub const PREFS: [Pref; 16] = [
    Pref {
        key: "theme_mode",
        validate: |v| exact(crate::theme::normalize_mode(v), v),
        set: |s, v| s.theme_mode = v,
    },
    Pref {
        key: "primary_color",
        validate: color,
        set: |s, v| s.primary_color = v,
    },
    Pref {
        key: "secondary_color",
        validate: color,
        set: |s, v| s.secondary_color = v,
    },
    Pref {
        key: "note_color",
        validate: color,
        set: |s, v| s.note_color = v,
    },
    Pref {
        key: "note_style",
        validate: |v| exact(crate::theme::normalize_note_style(v), v),
        set: |s, v| s.note_style = v,
    },
    Pref {
        key: "note_palette",
        validate: |v| exact(crate::theme::normalize_note_palette(v), v),
        set: |s, v| s.note_palette = v,
    },
    Pref {
        key: "markdown_style",
        validate: text,
        set: |s, v| s.markdown_style = v,
    },
    Pref {
        key: "spell_check",
        validate: |v| matches!(v, "true" | "false").then(|| v.to_string()),
        set: |s, v| s.spell_check = v == "true",
    },
    Pref {
        key: "draft_agent",
        validate: |v| exact(crate::editor::normalize_agent(v), v),
        set: |s, v| s.draft_agent = v,
    },
    Pref {
        key: "draft_system_prompt",
        validate: text,
        set: |s, v| s.draft_system_prompt = v,
    },
    Pref {
        key: "draft_model",
        validate: crate::editor::model_name,
        set: |s, v| s.draft_model = v,
    },
    Pref {
        key: "ollama_endpoint",
        validate: crate::editor::endpoint,
        set: |s, v| s.ollama_endpoint = v,
    },
    Pref {
        key: "ollama_token",
        validate: crate::editor::token,
        set: |s, v| s.ollama_token = Secret(v),
    },
    Pref {
        key: "draft_effort",
        validate: |v| crate::editor::effort(v).map(String::from),
        set: |s, v| s.draft_effort = v,
    },
    Pref {
        key: "motion_setting",
        validate: |v| exact(crate::motion::normalize_setting(v), v),
        set: |s, v| s.reduce_motion = v,
    },
    Pref {
        key: "ui_scale",
        validate: |v| {
            let n: f64 = v.trim().parse().ok()?;
            n.is_finite().then(|| normalize_ui_scale(n).to_string())
        },
        set: |s, v| s.ui_scale = v.parse().unwrap_or(1.0),
    },
];

pub fn pref(key: &str) -> Option<&'static Pref> {
    PREFS.iter().find(|p| p.key == key)
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
        let path = self.dir.join("settings.json");
        let bytes = match fs::read(&path) {
            Ok(b) => b,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Settings::default(),
            Err(e) => {
                eprintln!("warning: could not read {}: {e}", path.display());
                self.set_aside(&path);
                return Settings::default();
            }
        };
        match serde_json::from_slice(&bytes) {
            Ok(settings) => Settings::sanitized(settings),
            Err(e) => {
                eprintln!("warning: could not parse {}: {e}", path.display());
                self.set_aside(&path);
                Settings::default()
            }
        }
    }

    /// Move an unusable settings file to `settings.json.bad` (replacing an
    /// older one) so the next save does not destroy it.
    fn set_aside(&self, path: &Path) {
        let bad = path.with_file_name("settings.json.bad");
        let _ = fs::remove_file(&bad);
        match fs::rename(path, &bad) {
            Ok(()) => eprintln!("warning: kept the unusable file as {}", bad.display()),
            Err(e) => eprintln!("warning: could not move {} aside: {e}", path.display()),
        }
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
    fn corrupt_settings_are_moved_aside_and_survive_a_save() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("settings.json");
        fs::write(&file, r#"{"agent_write": tr"#).unwrap();
        let config = config_in(dir.path());
        let settings = config.load_settings();
        assert!(!settings.agent_write);
        assert!(!file.exists());
        let bad = dir.path().join("settings.json.bad");
        assert_eq!(fs::read_to_string(&bad).unwrap(), r#"{"agent_write": tr"#);
        config.save_settings(&settings).unwrap();
        assert_eq!(fs::read_to_string(&bad).unwrap(), r#"{"agent_write": tr"#);
        assert!(file.exists());
    }

    #[test]
    fn missing_settings_fall_back_silently_without_a_bad_file() {
        let dir = tempfile::tempdir().unwrap();
        config_in(dir.path()).load_settings();
        assert!(!dir.path().join("settings.json.bad").exists());
    }

    #[test]
    fn unknown_settings_survive_load_and_save() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("settings.json"),
            r#"{"agent_write": true, "future_flag": {"a": 1}}"#,
        )
        .unwrap();
        let config = config_in(dir.path());
        let settings = config.load_settings();
        config.save_settings(&settings).unwrap();
        let text = fs::read_to_string(dir.path().join("settings.json")).unwrap();
        let v: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(v["future_flag"]["a"], 1);
        assert_eq!(v["agent_write"], true);
    }

    #[test]
    fn settings_without_extra_still_load_and_save_no_extra() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("settings.json"), r#"{"port": 8000}"#).unwrap();
        let config = config_in(dir.path());
        let settings = config.load_settings();
        assert_eq!(settings.port, 8000);
        assert!(settings.extra.is_empty());
        config.save_settings(&settings).unwrap();
        let text = fs::read_to_string(dir.path().join("settings.json")).unwrap();
        assert!(!text.contains("extra"));
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
        assert_eq!(settings.note_style, "user", "variable colors are opt-in");
        assert_eq!(settings.note_palette, "pastel");
        assert!(settings.spell_check, "spell check is on unless turned off");
        assert_eq!(settings.draft_agent, "claude_code");
        assert_eq!(settings.draft_system_prompt, "");
        assert_eq!(settings.draft_model, "");
        assert_eq!(settings.draft_effort, "");
        assert_eq!(settings.ollama_endpoint, "http://localhost:11434");
        assert_eq!(settings.ollama_token, Secret::default());
        assert_eq!(settings.markdown_style, "default");
    }

    #[test]
    fn ollama_choices_survive_a_restart_and_the_token_is_never_debug_printed() {
        let dir = tempfile::tempdir().unwrap();
        let config = config_in(dir.path());
        let mut settings = config.load_settings();
        settings.draft_agent = "ollama".into();
        settings.draft_model = "llama3.2:3b".into();
        settings.ollama_endpoint = "https://llm.example.com:8080".into();
        settings.ollama_token = Secret("s3cr3t-token".into());
        config.save_settings(&settings).unwrap();

        let restored = config_in(dir.path()).load_settings();
        assert_eq!(restored.draft_agent, "ollama");
        assert_eq!(restored.draft_model, "llama3.2:3b", "free text for Ollama");
        assert_eq!(restored.ollama_endpoint, "https://llm.example.com:8080");
        assert_eq!(restored.ollama_token.0, "s3cr3t-token");
        assert!(!format!("{restored:?}").contains("s3cr3t-token"));
        assert!(!format!("{:?}", restored.ollama_token).contains("s3cr3t"));
    }

    #[test]
    fn invalid_ollama_values_in_a_file_load_as_defaults() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("settings.json"),
            r#"{"draft_agent": "claude_code", "draft_model": "llama3.2:3b",
                "ollama_endpoint": "ftp://nope", "ollama_token": "bad\ntoken"}"#,
        )
        .unwrap();
        let s = config_in(dir.path()).load_settings();
        assert_eq!(s.draft_model, "", "Claude Code only knows its aliases");
        assert_eq!(s.ollama_endpoint, "http://localhost:11434");
        assert_eq!(s.ollama_token.0, "");
    }

    #[test]
    fn ollama_prefs_are_validated() {
        let ok = |k: &str, v: &str, want: &str| {
            assert_eq!(validate(k, v).as_deref(), Some(want), "{k}={v}")
        };
        let bad = |k: &str, v: &str| assert_eq!(validate(k, v), None, "{k}={v}");
        ok("draft_agent", "ollama", "ollama");
        ok(
            "ollama_endpoint",
            " http://localhost:8080/ ",
            "http://localhost:8080",
        );
        ok(
            "ollama_endpoint",
            "https://h.example/api/",
            "https://h.example/api",
        );
        bad("ollama_endpoint", "localhost:11434");
        bad("ollama_endpoint", "ftp://h");
        bad("ollama_endpoint", "http://");
        bad("ollama_endpoint", "http://a b");
        bad("ollama_endpoint", "");
        ok("ollama_token", "", "");
        ok("ollama_token", "  abc123 ", "abc123");
        bad("ollama_token", "a\nb");
        ok("draft_model", "llama3.2:3b", "llama3.2:3b");
        bad("draft_model", "bad\nname");
    }

    #[test]
    fn prefs_json_carries_the_token_only_for_the_edit_field() {
        let s = Settings {
            ollama_token: Secret("tok-123".into()),
            ..Settings::default()
        };
        let v: serde_json::Value = serde_json::from_str(&s.prefs_json(false)).unwrap();
        assert_eq!(v["ollama_token"], "tok-123");
        assert_eq!(v["ollama_endpoint"], "http://localhost:11434");
    }

    #[test]
    fn editor_and_note_choices_survive_a_restart() {
        let dir = tempfile::tempdir().unwrap();
        let config = config_in(dir.path());
        let mut settings = config.load_settings();
        settings.note_color = "#bfe3ff".into();
        settings.note_style = "variable".into();
        settings.note_palette = "candy".into();
        settings.spell_check = false;
        settings.draft_system_prompt = "Write in British English.".into();
        settings.draft_model = "opus".into();
        settings.draft_effort = "high".into();
        settings.markdown_style = "reading".into();
        config.save_settings(&settings).unwrap();

        let restored = config_in(dir.path()).load_settings();
        assert_eq!(restored.note_color, "#bfe3ff");
        assert_eq!(restored.note_style, "variable");
        assert_eq!(restored.note_palette, "candy");
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

    #[test]
    fn invalid_values_in_a_settings_file_load_as_defaults() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("settings.json"),
            r##"{"theme_mode": "neon", "primary_color": "red", "secondary_color": "#12",
                "note_color": "#gggggg", "note_style": "rainbow", "note_palette": "neon",
                "reduce_motion": "maybe", "draft_agent": "x",
                "draft_model": "gpt", "draft_effort": "ludicrous", "port": 9000}"##,
        )
        .unwrap();
        let s = config_in(dir.path()).load_settings();
        let d = Settings::default();
        assert_eq!(s.theme_mode, d.theme_mode);
        assert_eq!(s.primary_color, d.primary_color);
        assert_eq!(s.secondary_color, d.secondary_color);
        assert_eq!(s.note_color, d.note_color);
        assert_eq!(s.note_style, d.note_style);
        assert_eq!(s.note_palette, d.note_palette);
        assert_eq!(s.reduce_motion, d.reduce_motion);
        assert_eq!(s.draft_agent, d.draft_agent);
        assert_eq!(s.draft_model, d.draft_model);
        assert_eq!(s.draft_effort, d.draft_effort);
        assert_eq!(s.port, 9000);
    }

    fn validate(key: &str, value: &str) -> Option<String> {
        (pref(key).expect(key).validate)(value)
    }

    #[test]
    fn pref_validators_accept_valid_values_and_reject_invalid_ones() {
        let ok = |k: &str, v: &str, want: &str| {
            assert_eq!(validate(k, v).as_deref(), Some(want), "{k}={v}")
        };
        let bad = |k: &str, v: &str| assert_eq!(validate(k, v), None, "{k}={v}");
        ok("theme_mode", "dark", "dark");
        ok("theme_mode", " Light ", "light");
        bad("theme_mode", "neon");
        bad("theme_mode", "");
        for k in ["primary_color", "secondary_color", "note_color"] {
            ok(k, "#FFF", "#ffffff");
            ok(k, "#ff8800", "#ff8800");
            ok(k, "", ""); // reset to the theme's default
            bad(k, "red");
            bad(k, "#12345");
        }
        ok("note_style", "variable", "variable");
        ok("note_style", " User ", "user");
        bad("note_style", "rainbow");
        bad("note_style", "");
        ok("note_palette", "soft-earth", "soft-earth");
        ok("note_palette", "Cool", "cool");
        bad("note_palette", "neon");
        bad("note_palette", "");
        ok("markdown_style", "reading", "reading");
        ok("spell_check", "true", "true");
        ok("spell_check", "false", "false");
        bad("spell_check", "yes");
        ok("draft_agent", "claude_code", "claude_code");
        bad("draft_agent", "other");
        bad("draft_agent", "");
        ok("draft_system_prompt", "Be brief.", "Be brief.");
        ok("draft_system_prompt", "", "");
        ok("draft_model", "opus", "opus");
        ok("draft_model", "", "");
        ok("draft_effort", "high", "high");
        ok("draft_effort", "", "");
        bad("draft_effort", "ludicrous");
        ok("motion_setting", "on", "on");
        ok("motion_setting", "system", "system");
        bad("motion_setting", "maybe");
        bad("motion_setting", "");
        ok("ui_scale", "1.2", "1.2");
        ok("ui_scale", "0.1", "0.7");
        ok("ui_scale", "5", "2");
        bad("ui_scale", "big");
        bad("ui_scale", "NaN");
        bad("ui_scale", "");
        assert!(pref("port").is_none());
    }

    #[test]
    fn choosing_and_resetting_prefs_updates_settings_and_json() {
        let mut s = Settings::default();
        let set = |s: &mut Settings, k: &str, v: &str| {
            let p = pref(k).unwrap();
            (p.set)(s, (p.validate)(v).unwrap());
        };
        set(&mut s, "primary_color", "#ff8800");
        set(&mut s, "note_color", "#bfe3ff");
        set(&mut s, "motion_setting", "on");
        set(&mut s, "spell_check", "false");
        let v: serde_json::Value = serde_json::from_str(&s.prefs_json(false)).unwrap();
        assert_eq!(v["note_style"], "user");
        assert_eq!(v["note_palette"], "pastel");
        set(&mut s, "note_style", "variable");
        set(&mut s, "note_palette", "cool");
        let v: serde_json::Value = serde_json::from_str(&s.prefs_json(false)).unwrap();
        assert_eq!(v["note_style"], "variable");
        assert_eq!(v["note_palette"], "cool");
        assert_eq!(v["primary_color"], "#ff8800");
        assert_eq!(v["motion_setting"], "on");
        assert_eq!(v["reduce_motion"], true);
        assert_eq!(v["spell_check"], false);
        set(&mut s, "primary_color", "");
        set(&mut s, "note_color", "");
        assert_eq!(s.primary_color, "");
        assert_eq!(s.note_color, "");
        set(&mut s, "motion_setting", "system");
        let v: serde_json::Value = serde_json::from_str(&s.prefs_json(true)).unwrap();
        assert_eq!(v["reduce_motion"], true);
        let v: serde_json::Value = serde_json::from_str(&s.prefs_json(false)).unwrap();
        assert_eq!(v["reduce_motion"], false);
    }

    #[test]
    fn ui_scale_defaults_loads_old_files_and_is_clamped() {
        assert_eq!(Settings::default().ui_scale, 1.0);
        let dir = tempfile::tempdir().unwrap();
        // A settings file from before the scale existed.
        fs::write(dir.path().join("settings.json"), r#"{"port": 9000}"#).unwrap();
        assert_eq!(config_in(dir.path()).load_settings().ui_scale, 1.0);
        fs::write(dir.path().join("settings.json"), r#"{"ui_scale": 9}"#).unwrap();
        assert_eq!(config_in(dir.path()).load_settings().ui_scale, 2.0);
        fs::write(dir.path().join("settings.json"), r#"{"ui_scale": 0.2}"#).unwrap();
        assert_eq!(config_in(dir.path()).load_settings().ui_scale, 0.7);
        let mut s = Settings::default();
        let p = pref("ui_scale").unwrap();
        (p.set)(&mut s, (p.validate)("1.5").unwrap());
        let v: serde_json::Value = serde_json::from_str(&s.prefs_json(false)).unwrap();
        assert_eq!(v["ui_scale"], 1.5);
    }
}
