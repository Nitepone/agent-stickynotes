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
