//! Which backend drafts, according to the user's settings. Read on every run,
//! so a change in Preferences applies to the next draft.

use std::sync::Arc;

use super::DraftBackend;
use super::ollama::OllamaBackend;
use crate::editor;
use crate::settings::Settings;

/// The Ollama-style backend when `draft_agent` is `ollama`, otherwise `claude`.
pub fn select(settings: &Settings, claude: &Arc<dyn DraftBackend>) -> Arc<dyn DraftBackend> {
    if settings.draft_agent == editor::OLLAMA {
        Arc::new(OllamaBackend::new(
            settings.ollama_endpoint.clone(),
            settings.ollama_token.0.clone(),
        ))
    } else {
        claude.clone()
    }
}

/// The model to put in a request: free text for Ollama, a known alias (or
/// nothing) for Claude Code.
pub fn model_for(settings: &Settings) -> String {
    if settings.draft_agent == editor::OLLAMA {
        settings.draft_model.trim().to_string()
    } else {
        editor::model(&settings.draft_model)
            .unwrap_or_default()
            .to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::drafting::claude_code::ClaudeCodeBackend;

    fn claude() -> Arc<dyn DraftBackend> {
        Arc::new(ClaudeCodeBackend::new("claude"))
    }

    #[test]
    fn claude_code_is_used_unless_ollama_is_selected() {
        let mut settings = Settings::default();
        assert_eq!(select(&settings, &claude()).name(), "Claude Code");
        settings.draft_agent = "ollama".into();
        assert_eq!(select(&settings, &claude()).name(), "Ollama");
        settings.draft_agent = "claude_code".into();
        assert_eq!(select(&settings, &claude()).name(), "Claude Code");
    }

    #[test]
    fn the_model_is_free_text_only_for_ollama() {
        let mut settings = Settings {
            draft_model: "llama3.2:3b".into(),
            ..Settings::default()
        };
        assert_eq!(model_for(&settings), "", "Claude Code only gets aliases");
        settings.draft_model = "opus".into();
        assert_eq!(model_for(&settings), "opus");
        settings.draft_agent = "ollama".into();
        settings.draft_model = " llama3.2:3b ".into();
        assert_eq!(model_for(&settings), "llama3.2:3b");
    }
}
