//! The reduced-motion preference. When it is on, animated effects (the note
//! glow's rotation and sheen) are replaced by static ones.
//!
//! The user's choice is `system` (follow the desktop's animation setting),
//! `on` or `off`. Qt has no API for the desktop setting, so it is read from
//! the desktop environment where possible.

use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub const SYSTEM: &str = "system";
pub const ON: &str = "on";
pub const OFF: &str = "off";

/// `"system"`, `"on"` or `"off"`; anything else is `"system"`.
pub fn normalize_setting(setting: &str) -> &'static str {
    match setting.trim().to_ascii_lowercase().as_str() {
        "on" => ON,
        "off" => OFF,
        _ => SYSTEM,
    }
}

/// Whether motion should be reduced, given the user's setting and what the
/// desktop prefers.
pub fn effective(setting: &str, system_prefers_reduced: bool) -> bool {
    match normalize_setting(setting) {
        ON => true,
        OFF => false,
        _ => system_prefers_reduced,
    }
}

/// Best-effort read of the desktop's "reduce animations" preference.
/// `STICKYNOTES_REDUCE_MOTION=1|0` overrides it (handy for testing).
pub fn system_prefers_reduced_motion() -> bool {
    if let Ok(value) = std::env::var("STICKYNOTES_REDUCE_MOTION") {
        return matches!(value.trim(), "1" | "true" | "yes" | "on");
    }
    // GNOME and most GTK desktops.
    if let Some(out) = run(
        "gsettings",
        &["get", "org.gnome.desktop.interface", "enable-animations"],
    ) && let Some(enabled) = parse_bool(&out)
    {
        return !enabled;
    }
    // KDE: an animation speed factor of 0 means animations are off.
    if let Some(out) = run(
        "kreadconfig6",
        &[
            "--file",
            "kdeglobals",
            "--group",
            "KDE",
            "--key",
            "AnimationDurationFactor",
        ],
    ) && let Some(factor) = parse_factor(&out)
    {
        return factor == 0.0;
    }
    false
}

fn parse_bool(output: &str) -> Option<bool> {
    match output.trim() {
        "true" => Some(true),
        "false" => Some(false),
        _ => None,
    }
}

fn parse_factor(output: &str) -> Option<f64> {
    output.trim().parse().ok()
}

/// Run a command and return its stdout, giving up quickly so a missing or
/// stuck helper cannot delay startup.
fn run(program: &str, args: &[&str]) -> Option<String> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let started = Instant::now();
    loop {
        match child.try_wait().ok()? {
            Some(status) if status.success() => {
                let mut out = String::new();
                child.stdout.take()?.read_to_string(&mut out).ok()?;
                return Some(out);
            }
            Some(_) => return None,
            None if started.elapsed() > Duration::from_millis(800) => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
            None => std::thread::sleep(Duration::from_millis(10)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_default_to_following_the_system() {
        assert_eq!(normalize_setting("on"), "on");
        assert_eq!(normalize_setting(" OFF "), "off");
        assert_eq!(normalize_setting("system"), "system");
        assert_eq!(normalize_setting(""), "system");
        assert_eq!(normalize_setting("maybe"), "system");
    }

    #[test]
    fn the_users_choice_wins_over_the_system() {
        assert!(effective("on", false));
        assert!(!effective("off", true));
        assert!(effective("system", true));
        assert!(!effective("system", false));
        assert!(
            effective("garbage", true),
            "unknown values follow the system"
        );
    }

    #[test]
    fn desktop_output_is_parsed() {
        assert_eq!(parse_bool("true\n"), Some(true));
        assert_eq!(parse_bool("false\n"), Some(false));
        assert_eq!(parse_bool("'maybe'"), None);
        assert_eq!(parse_factor("0\n"), Some(0.0));
        assert_eq!(parse_factor("1.5"), Some(1.5));
        assert_eq!(parse_factor("n/a"), None);
    }

    #[test]
    fn a_missing_helper_is_not_an_error() {
        assert_eq!(run("definitely-not-a-real-program-xyz", &[]), None);
    }
}
