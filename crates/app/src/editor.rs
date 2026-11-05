//! Editor preferences: validation of the draft agent's options, and the spell
//! checker behind the underlines in the task editor. The editor itself is QML;
//! this only decides what is valid and which words to flag.

use std::fs;
use std::path::{Path, PathBuf};

use spellbook::Dictionary;

/// Claude Code run as a subshell (the default draft agent).
pub const CLAUDE_CODE: &str = "claude_code";
/// An Ollama-style server (Ollama, llama.cpp's `llama-server`, ...) over HTTP.
pub const OLLAMA: &str = "ollama";
/// Draft agent types offered in preferences (the first is the default).
pub const AGENTS: [&str; 2] = [CLAUDE_CODE, OLLAMA];
pub const DEFAULT_OLLAMA_ENDPOINT: &str = "http://localhost:11434";
/// Claude Code model aliases; empty is Claude Code's own default.
pub const MODELS: [&str; 5] = ["", "fable", "opus", "sonnet", "haiku"];
/// Claude Code effort ("thinking") levels; empty is its default.
pub const EFFORTS: [&str; 6] = ["", "low", "medium", "high", "xhigh", "max"];

fn pick(choices: &'static [&'static str], value: &str) -> Option<&'static str> {
    let value = value.trim();
    choices
        .iter()
        .copied()
        .find(|c| c.eq_ignore_ascii_case(value))
}

/// A known draft agent type; anything else is Claude Code.
pub fn normalize_agent(value: &str) -> &'static str {
    pick(&AGENTS, value).unwrap_or(CLAUDE_CODE)
}

/// A known model alias, or `None` for text that is not one. Empty is valid.
pub fn model(value: &str) -> Option<&'static str> {
    pick(&MODELS, value)
}

/// A model name for an Ollama-style server: free text without control
/// characters. Empty is valid here; drafting then asks for a model to be set.
pub fn model_name(value: &str) -> Option<String> {
    let value = value.trim();
    (value.chars().count() <= 200 && !value.chars().any(char::is_control))
        .then(|| value.to_string())
}

/// The base URL of an Ollama-style server: `http` or `https` with a host, no
/// spaces. A trailing slash is removed. Empty is not valid.
pub fn endpoint(value: &str) -> Option<String> {
    let value = value.trim().trim_end_matches('/');
    let rest = value
        .strip_prefix("http://")
        .or_else(|| value.strip_prefix("https://"))?;
    let host = rest.split(['/', '?', '#']).next().unwrap_or_default();
    let ok = !host.is_empty()
        && !host.starts_with(':')
        && !host.contains('@')
        && value.len() <= 2000
        && !value.chars().any(|c| c.is_whitespace() || c.is_control());
    ok.then(|| value.to_string())
}

/// An auth token: no whitespace or control characters, so it is safe in a
/// header. Empty means no token.
pub fn token(value: &str) -> Option<String> {
    let value = value.trim();
    (value.len() <= 4096 && !value.chars().any(|c| c.is_whitespace() || c.is_control()))
        .then(|| value.to_string())
}

/// A known effort level, or `None` for text that is not one. Empty is valid.
pub fn effort(value: &str) -> Option<&'static str> {
    pick(&EFFORTS, value)
}

/// Spell checking against a Hunspell dictionary (`.aff` + `.dic`).
pub struct SpellChecker {
    dictionary: Option<Dictionary>,
}

impl SpellChecker {
    /// Look for a dictionary for the user's language, falling back to
    /// American English. Without one nothing is ever flagged.
    pub fn load() -> Self {
        let mut stems = Vec::new();
        for var in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            if let Ok(value) = std::env::var(var)
                && let Some(lang) = value.split('.').next()
                && lang.len() == 5
                && lang.as_bytes()[2] == b'_'
            {
                stems.push(lang.to_string());
                break;
            }
        }
        stems.push("en_US".into());

        for dir in dictionary_dirs() {
            for stem in &stems {
                if let Some(dictionary) = read_dictionary(&dir, stem) {
                    return SpellChecker {
                        dictionary: Some(dictionary),
                    };
                }
            }
        }
        SpellChecker { dictionary: None }
    }

    #[cfg(test)]
    pub fn from_dictionary(aff: &str, dic: &str) -> Self {
        SpellChecker {
            dictionary: Dictionary::new(aff, dic).ok(),
        }
    }

    /// Whether a dictionary was found.
    pub fn available(&self) -> bool {
        self.dictionary.is_some()
    }

    /// Misspelled words in `text` as `(start, length)` in UTF-16 code units,
    /// which is how QML counts positions.
    pub fn misspelled(&self, text: &str) -> Vec<(usize, usize)> {
        let Some(dictionary) = &self.dictionary else {
            return Vec::new();
        };
        let mut found = Vec::new();
        for word in words(text) {
            if is_exempt(&word.text) {
                continue;
            }
            let normalized = word.text.replace('\u{2019}', "'");
            if !dictionary.check(&normalized) {
                found.push((word.start, word.len));
            }
        }
        found
    }

    /// Up to `max` replacements for `word`, best first; none without a
    /// dictionary or for a word that is spelled right.
    pub fn suggestions(&self, word: &str, max: usize) -> Vec<String> {
        let Some(dictionary) = &self.dictionary else {
            return Vec::new();
        };
        let normalized = word.trim().replace('\u{2019}', "'");
        if normalized.is_empty() || dictionary.check(&normalized) {
            return Vec::new();
        }
        let mut found = Vec::new();
        dictionary.suggest(&normalized, &mut found);
        let mut unique: Vec<String> = Vec::new();
        for s in found {
            if !unique.contains(&s) {
                unique.push(s);
            }
        }
        unique.truncate(max);
        unique
    }
}

fn dictionary_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Some(dir) = std::env::var_os("STICKYNOTES_DICT_DIR") {
        dirs.push(PathBuf::from(dir));
    }
    // Dictionaries shipped next to the executable (release packages).
    if let Ok(exe) = std::env::current_exe()
        && let Some(parent) = exe.parent()
    {
        dirs.push(parent.join("dictionaries"));
        dirs.push(parent.join("../share/stickynotes/dictionaries"));
    }
    for dir in [
        "/usr/share/hunspell",
        "/usr/share/myspell",
        "/usr/share/myspell/dicts",
        "/usr/local/share/hunspell",
        "/opt/homebrew/share/hunspell",
        "/Library/Spelling",
    ] {
        dirs.push(PathBuf::from(dir));
    }
    if let Some(home) = std::env::var_os("HOME") {
        dirs.push(Path::new(&home).join("Library/Spelling"));
    }
    dirs
}

fn read_dictionary(dir: &Path, stem: &str) -> Option<Dictionary> {
    let aff = fs::read_to_string(dir.join(format!("{stem}.aff"))).ok()?;
    let dic = fs::read_to_string(dir.join(format!("{stem}.dic"))).ok()?;
    Dictionary::new(&aff, &dic).ok()
}

/// A word to check, with its position in UTF-16 code units.
struct Word {
    start: usize,
    len: usize,
    text: String,
}

/// The words of `text` worth checking. Whole whitespace-separated chunks that
/// look like code, paths, addresses or numbers are skipped, and hyphenated
/// words are checked part by part.
fn words(text: &str) -> Vec<Word> {
    let mut result = Vec::new();
    let mut units = 0; // UTF-16 offset of `chunk_start`
    let mut chars = text.char_indices().peekable();
    while let Some((i, c)) = chars.next() {
        if c.is_whitespace() {
            units += c.len_utf16();
            continue;
        }
        // One chunk: up to the next whitespace.
        let mut end = i + c.len_utf8();
        while let Some(&(j, d)) = chars.peek() {
            if d.is_whitespace() {
                break;
            }
            end = j + d.len_utf8();
            chars.next();
        }
        let chunk = &text[i..end];
        let chunk_units = chunk.encode_utf16().count();
        collect_chunk(chunk, units, &mut result);
        units += chunk_units;
    }
    result
}

fn is_word_char(c: char) -> bool {
    c.is_alphabetic() || c == '\'' || c == '\u{2019}'
}

fn collect_chunk(chunk: &str, offset: usize, out: &mut Vec<Word>) {
    // Skip things that are not prose: file names, URLs, addresses, snake_case,
    // identifiers with digits.
    let core = chunk.trim_matches(|c: char| !c.is_alphanumeric());
    if core
        .chars()
        .any(|c| c.is_ascii_digit() || "_/\\@:#~=<>".contains(c))
    {
        return;
    }
    let inner = core.trim_end_matches('.');
    if inner.contains('.') {
        return;
    }

    let mut unit = offset;
    let mut word = String::new();
    let mut word_start = offset;
    let is_apostrophe = |c: char| c == '\'' || c == '\u{2019}';
    let flush = |word: &mut String, start: usize, out: &mut Vec<Word>| {
        let trimmed = word.trim_matches(is_apostrophe);
        if !trimmed.is_empty() {
            let lead = word.len() - word.trim_start_matches(is_apostrophe).len();
            out.push(Word {
                start: start + word[..lead].encode_utf16().count(),
                len: trimmed.encode_utf16().count(),
                text: trimmed.to_string(),
            });
        }
        word.clear();
    };
    for c in chunk.chars() {
        if is_word_char(c) {
            if word.is_empty() {
                word_start = unit;
            }
            word.push(c);
        } else {
            flush(&mut word, word_start, out);
        }
        unit += c.len_utf16();
    }
    flush(&mut word, word_start, out);
}

/// Acronyms (`HTTP`) and mixed-case names (`GitHub`, `macOS`) are not prose.
fn is_exempt(word: &str) -> bool {
    let letters: Vec<char> = word.chars().filter(|c| c.is_alphabetic()).collect();
    if letters.len() < 2 {
        return letters.is_empty();
    }
    let upper = letters.iter().filter(|c| c.is_uppercase()).count();
    if upper == letters.len() {
        return true;
    }
    // An uppercase letter after the first that follows a lowercase one.
    letters
        .windows(2)
        .any(|w| w[0].is_lowercase() && w[1].is_uppercase())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn checker() -> SpellChecker {
        SpellChecker::from_dictionary(
            "SET UTF-8\n",
            "11\nhello\nworld\nit's\nthe\nquick\nbrown\nfox\nbrown-ish\nsee\nand\nish\n",
        )
    }

    fn flagged(text: &str) -> Vec<String> {
        let units: Vec<u16> = text.encode_utf16().collect();
        checker()
            .misspelled(text)
            .into_iter()
            .map(|(start, len)| String::from_utf16(&units[start..start + len]).unwrap())
            .collect()
    }

    #[test]
    fn misspelled_words_get_suggestions_and_correct_ones_none() {
        let c = checker();
        let wrold = c.suggestions("wrold", 5);
        assert_eq!(
            wrold.first().map(String::as_str),
            Some("world"),
            "{wrold:?}"
        );
        assert!(c.suggestions("brwn", 5).contains(&"brown".to_string()));
        assert!(c.suggestions("world", 5).is_empty());
        assert!(c.suggestions("", 5).is_empty());
        assert!(c.suggestions("qzxjv", 5).len() <= 5);
        assert!(c.suggestions("wrold", 1).len() <= 1);
        let none = SpellChecker { dictionary: None };
        assert!(none.suggestions("wrold", 5).is_empty());
    }

    #[test]
    fn unknown_words_are_flagged_with_their_position() {
        let text = "hello wrold";
        assert_eq!(checker().misspelled(text), vec![(6, 5)]);
        assert_eq!(flagged("The quick brwn fox"), ["brwn"]);
    }

    #[test]
    fn known_words_and_case_variants_are_fine() {
        assert!(flagged("Hello, World! It's the fox.").is_empty());
    }

    #[test]
    fn punctuation_and_apostrophes_are_handled() {
        assert_eq!(flagged("(helo) 'wrold'."), ["helo", "wrold"]);
        assert!(flagged("it\u{2019}s").is_empty(), "curly apostrophes count");
    }

    #[test]
    fn hyphenated_words_are_checked_in_parts() {
        assert_eq!(flagged("brown-ish brown-foo"), ["foo"]);
    }

    #[test]
    fn code_paths_and_numbers_are_not_prose() {
        let text = "see crates/app/src/main.rs and snake_case, v2 foo@bar.com https://example.org \
                    3.14 HTTP GitHub macOS camelCase";
        assert!(flagged(text).is_empty(), "{:?}", flagged(text));
    }

    #[test]
    fn positions_count_utf16_units_not_bytes() {
        // The emoji takes two UTF-16 units; é takes one (but two bytes).
        let text = "\u{1F600} héllo wrold";
        let found = checker().misspelled(text);
        let units: Vec<u16> = text.encode_utf16().collect();
        let words: Vec<String> = found
            .iter()
            .map(|&(s, l)| String::from_utf16(&units[s..s + l]).unwrap())
            .collect();
        assert_eq!(words, ["héllo", "wrold"]);
    }

    #[test]
    fn newlines_separate_words() {
        assert_eq!(flagged("hello\nwrold\n\nfoox"), ["wrold", "foox"]);
    }

    #[test]
    fn without_a_dictionary_nothing_is_flagged() {
        let none = SpellChecker::from_dictionary("", "not a dictionary");
        assert!(!none.available());
        assert!(none.misspelled("wrold").is_empty());
    }

    #[test]
    fn draft_agent_options_are_validated() {
        assert_eq!(normalize_agent("claude_code"), "claude_code");
        assert_eq!(normalize_agent("OLLAMA"), "ollama");
        assert_eq!(normalize_agent("something else"), "claude_code");
        assert_eq!(model("Opus"), Some("opus"));
        assert_eq!(model(""), Some(""));
        assert_eq!(model("gpt"), None);
        assert_eq!(effort(" HIGH "), Some("high"));
        assert_eq!(effort("extreme"), None);
    }
}
