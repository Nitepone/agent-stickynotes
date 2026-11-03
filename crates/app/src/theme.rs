//! Validation of the user's theme choices. The colors themselves live in
//! `qml/Theme.qml`; this only makes sure what is stored and handed to QML is
//! well formed.

pub const LIGHT: &str = "light";
pub const DARK: &str = "dark";

/// `"light"` or `"dark"`; anything else (including nothing) is light.
pub fn normalize_mode(mode: &str) -> &'static str {
    if mode.trim().eq_ignore_ascii_case(DARK) {
        DARK
    } else {
        LIGHT
    }
}

/// How notes are colored: one user-chosen color, or a palette color per category.
pub const NOTE_STYLES: [&str; 2] = ["user", "variable"];
/// Ids of the note palettes in `Theme.qml` (`notePalettes`); the first is the default.
pub const NOTE_PALETTES: [&str; 4] = ["pastel", "soft-earth", "candy", "cool"];

/// A known note style, else the default (`user`).
pub fn normalize_note_style(style: &str) -> &'static str {
    let style = style.trim();
    NOTE_STYLES
        .into_iter()
        .find(|s| s.eq_ignore_ascii_case(style))
        .unwrap_or(NOTE_STYLES[0])
}

/// A known palette id, else the first palette.
pub fn normalize_note_palette(id: &str) -> &'static str {
    let id = id.trim();
    NOTE_PALETTES
        .into_iter()
        .find(|p| p.eq_ignore_ascii_case(id))
        .unwrap_or(NOTE_PALETTES[0])
}

/// A user-chosen color as lowercase `#rrggbb`. `#rgb` is expanded. Returns
/// `None` if the text is not a color.
pub fn normalize_color(color: &str) -> Option<String> {
    let hex = color.trim().strip_prefix('#')?;
    if !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    match hex.len() {
        6 => Some(format!("#{}", hex.to_ascii_lowercase())),
        3 => {
            let expanded: String = hex.chars().flat_map(|c| [c, c]).collect();
            Some(format!("#{}", expanded.to_ascii_lowercase()))
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mode_defaults_to_light() {
        assert_eq!(normalize_mode("dark"), "dark");
        assert_eq!(normalize_mode(" DARK "), "dark");
        assert_eq!(normalize_mode("light"), "light");
        assert_eq!(normalize_mode(""), "light");
        assert_eq!(normalize_mode("solarized"), "light");
    }

    #[test]
    fn note_style_and_palette_fall_back_to_the_defaults() {
        assert_eq!(normalize_note_style("variable"), "variable");
        assert_eq!(normalize_note_style(" Variable "), "variable");
        assert_eq!(normalize_note_style("user"), "user");
        assert_eq!(normalize_note_style("rainbow"), "user");
        assert_eq!(normalize_note_style(""), "user");
        assert_eq!(normalize_note_palette("candy"), "candy");
        assert_eq!(normalize_note_palette("COOL"), "cool");
        assert_eq!(normalize_note_palette("nope"), "pastel");
        assert_eq!(normalize_note_palette(""), "pastel");
    }

    /// The ids accepted here must be exactly the palettes `Theme.qml` defines,
    /// in the same order, or a saved choice would silently fall back.
    #[test]
    fn note_palette_ids_match_theme_qml() {
        let qml = std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("qml/Theme.qml"),
        )
        .unwrap();
        let ids: Vec<&str> = qml
            .lines()
            .filter_map(|l| l.trim().strip_prefix("{ id: \""))
            .filter_map(|l| l.split('"').next())
            .collect();
        assert_eq!(ids, NOTE_PALETTES);
    }

    #[test]
    fn colors_are_normalized_or_rejected() {
        assert_eq!(normalize_color("#2563EB").as_deref(), Some("#2563eb"));
        assert_eq!(normalize_color("  #abc ").as_deref(), Some("#aabbcc"));
        for bad in [
            "", "red", "2563eb", "#12345", "#1234567", "#gggggg", "#12 456", "#",
        ] {
            assert_eq!(normalize_color(bad), None, "{bad:?}");
        }
    }

    /// Views must take every color from `Theme.qml`, or switching mode or
    /// accent colors would leave some of the UI behind.
    #[test]
    fn views_do_not_hard_code_colors() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("qml");
        let named = [
            "white", "black", "red", "green", "blue", "gray", "grey", "yellow", "orange", "purple",
            "pink", "cyan", "magenta", "brown", "silver", "gold",
        ];
        let mut offences = Vec::new();
        let mut checked = 0;
        for entry in std::fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            let name = path.file_name().unwrap().to_string_lossy().into_owned();
            if !name.ends_with(".qml") || name == "Theme.qml" {
                continue;
            }
            checked += 1;
            for (n, line) in std::fs::read_to_string(&path).unwrap().lines().enumerate() {
                let code = line.split("//").next().unwrap();
                let hex_literal = code.match_indices("\"#").any(|(i, _)| {
                    let rest = &code[i + 2..];
                    let digits = rest.chars().take_while(char::is_ascii_hexdigit).count();
                    matches!(digits, 3 | 4 | 6 | 8) && rest[digits..].starts_with('"')
                });
                let named_color = named.iter().any(|c| code.contains(&format!("\"{c}\"")));
                let computed = code.contains("Qt.rgba(") || code.contains("Qt.color(");
                if hex_literal || named_color || computed {
                    offences.push(format!("{name}:{}: {}", n + 1, line.trim()));
                }
            }
        }
        assert!(checked >= 10, "expected to scan the views, found {checked}");
        assert!(
            offences.is_empty(),
            "hard-coded colors outside Theme.qml:\n{}",
            offences.join("\n")
        );
    }

    /// Every font size must go through `Theme.fs()`, or it would ignore the
    /// interface scale (Ctrl+= / Ctrl+- / Ctrl+0).
    #[test]
    fn views_do_not_hard_code_font_sizes() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("qml");
        let mut offences = Vec::new();
        let mut checked = 0;
        for entry in std::fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            let name = path.file_name().unwrap().to_string_lossy().into_owned();
            if !name.ends_with(".qml") || name == "Theme.qml" {
                continue;
            }
            checked += 1;
            for (n, line) in std::fs::read_to_string(&path).unwrap().lines().enumerate() {
                if has_literal_font_size(line) {
                    offences.push(format!("{name}:{}: {}", n + 1, line.trim()));
                }
            }
        }
        assert!(checked >= 10, "expected to scan the views, found {checked}");
        assert!(
            offences.is_empty(),
            "literal font sizes outside Theme.qml (use Theme.fs):\n{}",
            offences.join("\n")
        );
    }

    /// True if `line` sets `pixelSize` or `pointSize` to a bare number.
    fn has_literal_font_size(line: &str) -> bool {
        let code = line.split("//").next().unwrap();
        ["pixelSize", "pointSize"].iter().any(|key| {
            code.match_indices(key).any(|(i, _)| {
                let rest = code[i + key.len()..].trim_start();
                rest.strip_prefix(':')
                    .or_else(|| rest.strip_prefix('='))
                    .is_some_and(|v| v.trim_start().starts_with(|c: char| c.is_ascii_digit()))
            })
        })
    }

    #[test]
    fn the_font_size_scan_would_catch_a_literal() {
        assert!(has_literal_font_size("    font.pixelSize: 12"));
        assert!(has_literal_font_size("font.pixelSize: 12 // note"));
        assert!(!has_literal_font_size("    font.pixelSize: Theme.fs(12)"));
        assert!(!has_literal_font_size("// font.pixelSize: 12"));
    }

    /// The style must not depend on the platform default or on the
    /// `QT_QUICK_CONTROLS_STYLE` variable: a plain `import QtQuick.Controls`
    /// lets Windows pick its own (light) style, and windeployqt only ships
    /// the style modules that some QML file imports.
    #[test]
    fn views_import_the_fusion_style_explicitly() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("qml");
        for entry in std::fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            if path.extension().is_some_and(|e| e == "qml") {
                let text = std::fs::read_to_string(&path).unwrap();
                assert!(
                    !text.lines().any(|l| l.trim() == "import QtQuick.Controls"),
                    "{} imports the platform-default style; use QtQuick.Controls.Fusion",
                    path.display()
                );
            }
        }
    }

    /// A `Binding` whose target is `window.palette` re-evaluates its own
    /// target when it writes (a binding loop), so it never applies.
    #[test]
    fn the_window_palette_is_set_in_its_palette_group() {
        let main = std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("qml/Main.qml"),
        )
        .unwrap();
        assert!(!main.contains("target: window.palette"));
        assert!(main.contains("shadow: Theme.shadeShadow"));
    }

    #[test]
    fn the_scan_would_catch_a_hard_coded_color() {
        // Guard against the scan above silently matching nothing.
        let code = r##"color: "#ff8800""##;
        let found = code.match_indices("\"#").any(|(i, _)| {
            let rest = &code[i + 2..];
            let digits = rest.chars().take_while(char::is_ascii_hexdigit).count();
            matches!(digits, 3 | 4 | 6 | 8) && rest[digits..].starts_with('"')
        });
        assert!(found);
    }
}
