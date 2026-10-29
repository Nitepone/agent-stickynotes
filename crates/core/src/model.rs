//! Board data model. This is exactly what is persisted to JSON.
//!
//! Every struct carries an `extra` map so fields written by a newer version
//! (or by hand) survive a load/save round trip.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use uuid::Uuid;

pub const SCHEMA_VERSION: u32 = 1;

/// Suggested (not enforced) maximum length of a task description.
pub const SUGGESTED_DESCRIPTION_CHARS: usize = 200;

pub type ColumnId = Uuid;
pub type TaskId = Uuid;
pub type CriterionId = Uuid;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Board {
    pub schema_version: u32,
    pub id: Uuid,
    pub title: String,
    /// Vec order is the stage order, left to right.
    #[serde(default)]
    pub columns: Vec<Column>,
    /// Project-level instructions for agents. Only the user edits these.
    #[serde(default, skip_serializing_if = "ProjectSettings::is_empty")]
    pub project: ProjectSettings,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

/// Instructions that apply to the whole board, shown to agents.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ProjectSettings {
    /// How agents should write documents (specs, reports, release notes).
    #[serde(default)]
    pub document_prompt: String,
    /// How code for this project should be written.
    #[serde(default)]
    pub code_guidance: String,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl ProjectSettings {
    pub fn is_empty(&self) -> bool {
        self.document_prompt.is_empty() && self.code_guidance.is_empty() && self.extra.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Column {
    pub id: ColumnId,
    pub title: String,
    /// What this stage means; doubles as the entry criteria agents must check.
    #[serde(default)]
    pub description: String,
    /// Vec order is the card order, top to bottom.
    #[serde(default)]
    pub tasks: Vec<Task>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Task {
    pub id: TaskId,
    pub description: String,
    #[serde(default)]
    pub extended_description: String,
    #[serde(default)]
    pub requirements: Vec<String>,
    #[serde(default)]
    pub acceptance_criteria: Vec<Criterion>,
    /// Links to other tasks. Every link has a mirror on the other task.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub references: Vec<Reference>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

/// How one task relates to another, read as "<this task> <relation> <other>".
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Relation {
    Blocks,
    BlockedBy,
    RelatesTo,
    Duplicates,
    DuplicatedBy,
}

impl Relation {
    pub const ALL: [Relation; 5] = [
        Relation::Blocks,
        Relation::BlockedBy,
        Relation::RelatesTo,
        Relation::Duplicates,
        Relation::DuplicatedBy,
    ];

    /// The relation as seen from the other task.
    pub fn inverse(self) -> Relation {
        match self {
            Relation::Blocks => Relation::BlockedBy,
            Relation::BlockedBy => Relation::Blocks,
            Relation::RelatesTo => Relation::RelatesTo,
            Relation::Duplicates => Relation::DuplicatedBy,
            Relation::DuplicatedBy => Relation::Duplicates,
        }
    }

    /// Stable identifier used in JSON, the API and MCP.
    pub fn as_str(self) -> &'static str {
        match self {
            Relation::Blocks => "blocks",
            Relation::BlockedBy => "blocked_by",
            Relation::RelatesTo => "relates_to",
            Relation::Duplicates => "duplicates",
            Relation::DuplicatedBy => "duplicated_by",
        }
    }

    /// Human-readable form for UIs and exports.
    pub fn label(self) -> &'static str {
        match self {
            Relation::Blocks => "blocks",
            Relation::BlockedBy => "is blocked by",
            Relation::RelatesTo => "relates to",
            Relation::Duplicates => "duplicates",
            Relation::DuplicatedBy => "is duplicated by",
        }
    }

    pub fn parse(s: &str) -> Option<Relation> {
        Relation::ALL.into_iter().find(|r| r.as_str() == s.trim())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Reference {
    pub task: TaskId,
    pub relation: Relation,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl Reference {
    pub fn new(task: TaskId, relation: Relation) -> Self {
        Reference {
            task,
            relation,
            extra: Map::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Criterion {
    pub id: CriterionId,
    pub text: String,
    #[serde(default)]
    pub done: bool,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

/// Acceptance-criteria progress for a task.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Progress {
    pub done: usize,
    pub total: usize,
}

impl Board {
    /// An empty board with the default workflow columns.
    pub fn new_default() -> Self {
        let columns = [
            ("Backlog", "Ideas and requests that have not been scoped yet."),
            (
                "To Do",
                "Scoped and ready to start: the description is clear and acceptance criteria are written.",
            ),
            (
                "In Progress",
                "Actively being worked on. Requirements are understood and work has started.",
            ),
            (
                "Review",
                "Implementation is complete and every acceptance criterion is checked off; awaiting review.",
            ),
            ("Done", "Reviewed and accepted. Nothing left to do."),
        ]
        .into_iter()
        .map(|(title, description)| Column::new(title, description))
        .collect();

        Board {
            schema_version: SCHEMA_VERSION,
            id: Uuid::new_v4(),
            title: "Untitled board".into(),
            columns,
            project: ProjectSettings::default(),
            extra: Map::new(),
        }
    }

    pub fn column_index(&self, id: ColumnId) -> Option<usize> {
        self.columns.iter().position(|c| c.id == id)
    }

    /// Returns `(column index, task index)` of a task.
    pub fn locate_task(&self, id: TaskId) -> Option<(usize, usize)> {
        self.columns
            .iter()
            .enumerate()
            .find_map(|(ci, col)| col.tasks.iter().position(|t| t.id == id).map(|ti| (ci, ti)))
    }

    pub fn task(&self, id: TaskId) -> Option<&Task> {
        self.locate_task(id)
            .map(|(ci, ti)| &self.columns[ci].tasks[ti])
    }

    pub fn task_mut(&mut self, id: TaskId) -> Option<&mut Task> {
        let (ci, ti) = self.locate_task(id)?;
        Some(&mut self.columns[ci].tasks[ti])
    }

    pub fn tasks(&self) -> impl Iterator<Item = (&Column, &Task)> {
        self.columns
            .iter()
            .flat_map(|c| c.tasks.iter().map(move |t| (c, t)))
    }
}

impl Column {
    pub fn new(title: impl Into<String>, description: impl Into<String>) -> Self {
        Column {
            id: Uuid::new_v4(),
            title: title.into(),
            description: description.into(),
            tasks: Vec::new(),
            extra: Map::new(),
        }
    }
}

impl Task {
    pub fn progress(&self) -> Progress {
        Progress {
            done: self.acceptance_criteria.iter().filter(|c| c.done).count(),
            total: self.acceptance_criteria.len(),
        }
    }
}

/// The text shown on a sticky note. Descriptions longer than the suggested
/// length (or than `max_lines`) are cut at a word boundary and end in `[...]`.
pub fn card_text(description: &str, max_chars: usize, max_lines: usize) -> String {
    let description = description.trim();
    let mut head = description;
    let mut truncated = false;

    if let Some((idx, _)) = head.char_indices().nth(max_chars) {
        head = &head[..idx];
        // Prefer to break on whitespace, unless that would drop most of the text.
        if let Some(ws) = head.rfind(char::is_whitespace).filter(|&ws| ws >= idx / 2) {
            head = &head[..ws];
        }
        truncated = true;
    }
    if let Some((idx, _)) = head.match_indices('\n').nth(max_lines.saturating_sub(1)) {
        head = &head[..idx];
        truncated = true;
    }
    if !truncated {
        return description.to_string();
    }

    format!("{} [...]", head.trim_end())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn card_text_short_is_unchanged() {
        assert_eq!(card_text("  fix the bug ", 200, 6), "fix the bug");
    }

    #[test]
    fn card_text_truncates_on_word_boundary() {
        let text = "alpha beta gamma delta";
        assert_eq!(card_text(text, 13, 6), "alpha beta [...]");
    }

    #[test]
    fn card_text_truncates_long_word() {
        assert_eq!(card_text("abcdefghij", 4, 6), "abcd [...]");
    }

    #[test]
    fn card_text_limits_lines() {
        assert_eq!(card_text("a\nb\nc\nd", 200, 2), "a\nb [...]");
    }

    #[test]
    fn card_text_handles_multibyte() {
        assert_eq!(card_text("ééééé", 3, 6), "ééé [...]");
    }

    #[test]
    fn exactly_max_chars_is_not_truncated() {
        let text = "x".repeat(200);
        assert_eq!(card_text(&text, 200, 6), text);
    }
}
