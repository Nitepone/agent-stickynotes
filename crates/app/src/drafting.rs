//! Drafting requirements and acceptance criteria for a task with an LLM.
//!
//! The UI talks only to the [`DraftBackend`] trait. Today the one backend runs
//! Claude Code as a subprocess ([`claude_code::ClaudeCodeBackend`]); an
//! Ollama-style HTTP endpoint or an embedded model can be added later by
//! implementing the same trait. Everything else in this module (prompt
//! building, reply parsing, de-duplication) is backend independent and free of
//! Qt so it can be unit tested.

pub mod claude_code;

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Everything a backend needs to know about the task being refined.
#[derive(Debug, Clone, Default, Serialize)]
pub struct DraftRequest {
    pub description: String,
    pub extended_description: String,
    pub requirements: Vec<String>,
    pub acceptance_criteria: Vec<String>,
    /// Project-level guidance, given to the model as context (not as ticket data).
    #[serde(skip)]
    pub document_prompt: String,
    #[serde(skip)]
    pub code_guidance: String,
    /// The user's draft agent preferences (Preferences > Editor).
    #[serde(skip)]
    pub options: DraftOptions,
}

/// How the user wants the draft agent run. Empty text means the backend's own
/// default.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DraftOptions {
    /// Added to the built-in system prompt, which fixes the reply format.
    pub system_prompt: String,
    pub model: String,
    pub effort: String,
}

/// New items proposed by a backend.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Draft {
    pub requirements: Vec<String>,
    pub acceptance_criteria: Vec<String>,
}

#[derive(Debug, Error)]
pub enum DraftError {
    #[error("{0}")]
    Unavailable(String),
    #[error("{0}")]
    Failed(String),
    #[error("{0}")]
    BadReply(String),
    #[error("generation timed out after {0} seconds")]
    TimedOut(u64),
    #[error("generation cancelled")]
    Cancelled,
}

impl DraftError {
    /// Stable identifier for the UI.
    pub fn code(&self) -> &'static str {
        match self {
            DraftError::Unavailable(_) => "unavailable",
            DraftError::Failed(_) => "failed",
            DraftError::BadReply(_) => "bad_reply",
            DraftError::TimedOut(_) => "timeout",
            DraftError::Cancelled => "cancelled",
        }
    }
}

/// Lets the UI stop a running generation.
#[derive(Debug, Clone, Default)]
pub struct CancelToken(Arc<AtomicBool>);

impl CancelToken {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.0.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::SeqCst)
    }
}

/// Something that can propose requirements and acceptance criteria for a task.
///
/// `generate` blocks; callers run it on a worker thread. Implementations must
/// poll `cancel` and return [`DraftError::Cancelled`] promptly when it is set.
pub trait DraftBackend: Send + Sync {
    /// Shown to the user, e.g. "Claude Code".
    fn name(&self) -> &str;

    fn generate(&self, request: &DraftRequest, cancel: &CancelToken) -> Result<Draft, DraftError>;
}

impl DraftRequest {
    /// The ticket as JSON, which is what the model is given to work from.
    pub fn ticket_json(&self) -> String {
        serde_json::to_string_pretty(self).expect("request serializes")
    }

    /// Instructions for the model: the task, the output format and the
    /// project's own guidance.
    pub fn system_prompt(&self) -> String {
        let mut prompt = String::from(
            "You are an assistant built into a kanban board app. You are given one task as JSON \
(description, extended_description, requirements, acceptance_criteria). Draft NEW requirements \
and acceptance criteria for it.

- A requirement is something the solution must do, or a constraint it must respect.
- An acceptance criterion is one condition that someone can check as pass or fail to decide \
that the task is done.

Rules:
- Base everything on the task. Do not invent unrelated scope.
- Do not repeat or reword items the task already has; add only what is missing.
- One condition per item, each under 160 characters, written as a plain statement.
- Give at most 6 requirements and 8 acceptance criteria. Fewer is fine. Use an empty list when \
nothing is missing.
- Reply with ONLY a JSON object, with no prose and no code fences:
  {\"requirements\": [\"...\"], \"acceptance_criteria\": [\"...\"]}",
        );
        for (heading, text) in [
            ("Project writing guidance", &self.document_prompt),
            ("Project code guidance", &self.code_guidance),
            (
                "Additional instructions from the user",
                &self.options.system_prompt,
            ),
        ] {
            if !text.trim().is_empty() {
                prompt.push_str(&format!("\n\n{heading} (follow it):\n{}", text.trim()));
            }
        }
        prompt
    }
}

#[derive(Deserialize)]
struct Reply {
    #[serde(default)]
    requirements: Vec<String>,
    #[serde(default, alias = "criteria")]
    acceptance_criteria: Vec<String>,
}

/// Turn a model's reply into a [`Draft`]. Tolerates code fences and a bit of
/// prose around the JSON object.
pub fn parse_reply(reply: &str) -> Result<Draft, DraftError> {
    let reply = reply.trim();
    let parsed = serde_json::from_str::<Reply>(reply)
        .ok()
        .or_else(|| {
            let start = reply.find('{')?;
            let end = reply.rfind('}')?;
            serde_json::from_str::<Reply>(reply.get(start..=end)?).ok()
        })
        .ok_or_else(|| {
            let snippet: String = reply.chars().take(200).collect();
            DraftError::BadReply(format!(
                "The reply was not the expected JSON. It began: {snippet}"
            ))
        })?;
    Ok(Draft {
        requirements: clean(parsed.requirements),
        acceptance_criteria: clean(parsed.acceptance_criteria),
    })
}

impl Draft {
    /// Drop items the task already has (ignoring case and spacing) and
    /// repeats within the draft, so adding the draft never duplicates anything.
    pub fn without_existing(self, request: &DraftRequest) -> Draft {
        Draft {
            requirements: only_new(self.requirements, &request.requirements),
            acceptance_criteria: only_new(self.acceptance_criteria, &request.acceptance_criteria),
        }
    }

    #[cfg(test)]
    pub fn is_empty(&self) -> bool {
        self.requirements.is_empty() && self.acceptance_criteria.is_empty()
    }
}

fn clean(items: Vec<String>) -> Vec<String> {
    items
        .into_iter()
        .map(|s| s.split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|s| !s.is_empty())
        .collect()
}

fn normalized(s: &str) -> String {
    s.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn only_new(items: Vec<String>, existing: &[String]) -> Vec<String> {
    let mut seen: Vec<String> = existing.iter().map(|s| normalized(s)).collect();
    let mut result = Vec::new();
    for item in items {
        let key = normalized(&item);
        if !seen.contains(&key) {
            seen.push(key);
            result.push(item);
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request() -> DraftRequest {
        DraftRequest {
            description: "Add a login page".into(),
            extended_description: "Users sign in with email.".into(),
            requirements: vec!["Use HTTPS".into()],
            acceptance_criteria: vec!["User can sign in".into()],
            document_prompt: "Plain English.".into(),
            code_guidance: String::new(),
            options: DraftOptions::default(),
        }
    }

    #[test]
    fn ticket_json_has_the_task_but_not_project_guidance() {
        let v: serde_json::Value = serde_json::from_str(&request().ticket_json()).unwrap();
        assert_eq!(v["description"], "Add a login page");
        assert_eq!(v["requirements"][0], "Use HTTPS");
        assert_eq!(v["acceptance_criteria"][0], "User can sign in");
        assert!(v.get("document_prompt").is_none());
    }

    #[test]
    fn system_prompt_states_the_format_and_includes_project_guidance() {
        let prompt = request().system_prompt();
        assert!(prompt.contains("\"acceptance_criteria\""));
        assert!(prompt.contains("ONLY a JSON object"));
        assert!(prompt.contains("Project writing guidance (follow it):\nPlain English."));
        assert!(
            !prompt.contains("Project code guidance"),
            "empty guidance is omitted"
        );
    }

    #[test]
    fn the_users_system_prompt_is_added_after_the_built_in_one() {
        let mut req = request();
        req.options.system_prompt = "  Write in British English.  ".into();
        let prompt = req.system_prompt();
        assert!(prompt.contains("ONLY a JSON object"), "format rules stay");
        assert!(
            prompt.ends_with(
                "Additional instructions from the user (follow it):\nWrite in British English."
            ),
            "{prompt}"
        );
        assert!(
            !request()
                .system_prompt()
                .contains("Additional instructions")
        );
    }

    #[test]
    fn parses_plain_json() {
        let d = parse_reply(r#"{"requirements":["a"],"acceptance_criteria":["b","c"]}"#).unwrap();
        assert_eq!(d.requirements, ["a"]);
        assert_eq!(d.acceptance_criteria, ["b", "c"]);
    }

    #[test]
    fn parses_fenced_json_with_prose() {
        let reply = "Sure! Here you go:\n```json\n{\"requirements\": [\"a\"], \"criteria\": [\"b\"]}\n```\nHope that helps.";
        let d = parse_reply(reply).unwrap();
        assert_eq!(d.requirements, ["a"]);
        assert_eq!(
            d.acceptance_criteria,
            ["b"],
            "`criteria` is accepted as an alias"
        );
    }

    #[test]
    fn missing_keys_mean_empty_lists() {
        let d = parse_reply(r#"{"requirements":["a"]}"#).unwrap();
        assert!(d.acceptance_criteria.is_empty());
        assert!(parse_reply("{}").unwrap().is_empty());
    }

    #[test]
    fn rejects_replies_without_json() {
        let err = parse_reply("I could not do that.").unwrap_err();
        assert_eq!(err.code(), "bad_reply");
        assert!(err.to_string().contains("I could not do that."));
        assert!(parse_reply(r#"{"requirements": "not a list"}"#).is_err());
    }

    #[test]
    fn cleans_whitespace_and_blanks() {
        let d = parse_reply(r#"{"requirements":["  spaced   out \n item ", "", "  "]}"#).unwrap();
        assert_eq!(d.requirements, ["spaced out item"]);
    }

    #[test]
    fn existing_items_and_repeats_are_dropped() {
        let draft = Draft {
            requirements: vec![
                "use https".into(),
                "Rate limit logins".into(),
                "RATE  limit logins".into(),
            ],
            acceptance_criteria: vec![
                "User can sign in ".into(),
                "Wrong password shows an error".into(),
            ],
        };
        let d = draft.without_existing(&request());
        assert_eq!(d.requirements, ["Rate limit logins"]);
        assert_eq!(d.acceptance_criteria, ["Wrong password shows an error"]);
    }

    #[test]
    fn cancel_token_is_shared_between_clones() {
        let token = CancelToken::new();
        let other = token.clone();
        assert!(!other.is_cancelled());
        token.cancel();
        assert!(other.is_cancelled());
    }
}
