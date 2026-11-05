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
pub type ArtifactId = Uuid;

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
    /// The number the next new task gets. Only ever increases, so a deleted
    /// task's number is never reused.
    #[serde(default)]
    pub next_number: u64,
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
    /// Short, permanent number ("#12") that people and agents use to refer
    /// to the task. Assigned once, when the task is created.
    #[serde(default)]
    pub number: u64,
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
    /// Files attached to this task, kept in the project's `artifacts/` folder.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub artifacts: Vec<Artifact>,
    /// Optional group name. Tasks sharing a category within a column stack in
    /// the UI. Spelling is unified across the board by the command layer.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    /// Set when the most recent change to this task was made by an agent, so
    /// the UI can draw attention to it. A change by the user clears it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_change: Option<AgentChange>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

/// What kind of file an artifact is, which decides how the viewer shows it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactKind {
    Markdown,
    Image,
    /// Opened in the system's PDF viewer, not inside the app.
    Pdf,
}

impl ArtifactKind {
    pub fn as_str(self) -> &'static str {
        match self {
            ArtifactKind::Markdown => "markdown",
            ArtifactKind::Image => "image",
            ArtifactKind::Pdf => "pdf",
        }
    }
}

/// A file attached to a task. The file itself lives in the project's
/// `artifacts/` folder; detaching removes this record and leaves the file.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Artifact {
    pub id: ArtifactId,
    /// The file's name inside `artifacts/`; also what is shown.
    pub name: String,
    pub kind: ArtifactKind,
    pub added_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub by_agent: bool,
    /// Who attached it: "user", or the agent client's name. Absent in old files.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub added_by: Option<String>,
    /// Title of the task's column when it was attached (a snapshot; renaming
    /// the column later does not change it). Absent in old files.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stage: Option<String>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

/// What an agent did to a task.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChangeKind {
    /// The agent created the task.
    Created,
    /// The agent moved it to another column.
    Moved,
    /// The agent ticked or unticked an acceptance criterion.
    Progress,
    /// The agent changed its text, requirements, criteria or links.
    Edited,
}

impl ChangeKind {
    pub fn as_str(self) -> &'static str {
        match self {
            ChangeKind::Created => "created",
            ChangeKind::Moved => "moved",
            ChangeKind::Progress => "progress",
            ChangeKind::Edited => "edited",
        }
    }
}

/// The latest change an agent made to a task.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentChange {
    pub at: DateTime<Utc>,
    pub kind: ChangeKind,
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
            next_number: 1,
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

    pub fn find_by_number(&self, number: u64) -> Option<&Task> {
        self.tasks().map(|(_, t)| t).find(|t| t.number == number)
    }

    /// Hand out the next task number.
    pub fn take_number(&mut self) -> u64 {
        if self.next_number == 0 {
            self.normalize();
        }
        let n = self.next_number;
        self.next_number += 1;
        n
    }

    /// Give every task a unique number: tasks without one (boards from
    /// before numbering) and later duplicates (hand-edited files) are numbered
    /// in creation order, and the counter is moved past every number in use.
    /// Returns whether anything changed.
    pub fn normalize(&mut self) -> bool {
        let before = (self.next_number, self.numbers());
        let mut order: Vec<(usize, usize)> = self
            .columns
            .iter()
            .enumerate()
            .flat_map(|(ci, c)| (0..c.tasks.len()).map(move |ti| (ci, ti)))
            .collect();
        order.sort_by_key(|&(ci, ti)| self.columns[ci].tasks[ti].created_at);

        let mut taken = std::collections::HashSet::new();
        let mut unnumbered = Vec::new();
        for &(ci, ti) in &order {
            let n = self.columns[ci].tasks[ti].number;
            if n == 0 || !taken.insert(n) {
                unnumbered.push((ci, ti));
            }
        }
        let mut next = self
            .next_number
            .max(taken.iter().max().map_or(1, |m| m + 1))
            .max(1);
        for (ci, ti) in unnumbered {
            self.columns[ci].tasks[ti].number = next;
            next += 1;
        }
        self.next_number = next;
        before != (self.next_number, self.numbers())
    }

    fn numbers(&self) -> Vec<u64> {
        self.tasks().map(|(_, t)| t.number).collect()
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

    // ---- task numbers ----

    fn bare_task(number: u64, created_secs: i64) -> Task {
        let at = DateTime::from_timestamp(1_700_000_000 + created_secs, 0).unwrap();
        Task {
            id: Uuid::new_v4(),
            number,
            description: format!("task created at +{created_secs}"),
            extended_description: String::new(),
            requirements: Vec::new(),
            acceptance_criteria: Vec::new(),
            references: Vec::new(),
            artifacts: Vec::new(),
            category: None,
            agent_change: None,
            created_at: at,
            updated_at: at,
            extra: Map::new(),
        }
    }

    fn numbers_in_creation_order(board: &Board) -> Vec<u64> {
        let mut tasks: Vec<_> = board.tasks().map(|(_, t)| t).collect();
        tasks.sort_by_key(|t| t.created_at);
        tasks.iter().map(|t| t.number).collect()
    }

    #[test]
    fn normalize_numbers_old_tasks_in_creation_order() {
        let mut board = Board::new_default();
        board.next_number = 0;
        // Created order: b (+10), a (+20), c (+30), but stored in other positions.
        board.columns[0].tasks = vec![bare_task(0, 20), bare_task(0, 10)];
        board.columns[3].tasks = vec![bare_task(0, 30)];
        assert!(board.normalize());
        assert_eq!(numbers_in_creation_order(&board), [1, 2, 3]);
        assert_eq!(board.next_number, 4);
        assert!(!board.normalize(), "already numbered: nothing changes");
    }

    #[test]
    fn normalize_keeps_existing_numbers_and_numbers_only_the_new_ones() {
        let mut board = Board::new_default();
        board.next_number = 0;
        board.columns[0].tasks = vec![bare_task(7, 10), bare_task(0, 20), bare_task(3, 30)];
        board.normalize();
        assert_eq!(numbers_in_creation_order(&board), [7, 8, 3]);
        assert_eq!(board.next_number, 9);
    }

    #[test]
    fn normalize_repairs_duplicates_keeping_the_oldest() {
        let mut board = Board::new_default();
        board.columns[0].tasks = vec![bare_task(5, 30), bare_task(5, 10), bare_task(5, 20)];
        board.next_number = 6;
        assert!(board.normalize());
        assert_eq!(numbers_in_creation_order(&board), [5, 6, 7]);
        let mut all: Vec<_> = board.tasks().map(|(_, t)| t.number).collect();
        all.sort();
        all.dedup();
        assert_eq!(all.len(), 3, "numbers are unique");
    }

    #[test]
    fn the_counter_never_falls_behind_the_highest_number() {
        let mut board = Board::new_default();
        board.next_number = 2;
        board.columns[0].tasks = vec![bare_task(40, 10)];
        board.normalize();
        assert_eq!(board.take_number(), 41);
        assert_eq!(board.take_number(), 42);
    }

    #[test]
    fn a_counter_ahead_of_the_tasks_is_kept_so_deleted_numbers_stay_retired() {
        let mut board = Board::new_default();
        board.next_number = 100;
        board.columns[0].tasks = vec![bare_task(3, 10)];
        assert!(!board.normalize());
        assert_eq!(board.take_number(), 100);
    }

    #[test]
    fn find_by_number() {
        let mut board = Board::new_default();
        board.columns[1].tasks = vec![bare_task(4, 1)];
        assert!(board.find_by_number(4).is_some());
        assert!(board.find_by_number(5).is_none());
    }

    #[test]
    fn boards_written_before_numbers_still_deserialize() {
        let legacy = r#"{"schema_version":1,"id":"00000000-0000-0000-0000-000000000001","title":"Old",
          "columns":[{"id":"00000000-0000-0000-0000-000000000002","title":"A","description":"",
            "tasks":[{"id":"00000000-0000-0000-0000-000000000003","description":"x",
              "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}]}]}"#;
        let mut board: Board = serde_json::from_str(legacy).unwrap();
        assert_eq!(board.columns[0].tasks[0].number, 0);
        assert!(board.normalize());
        assert_eq!(board.columns[0].tasks[0].number, 1);
        assert_eq!(board.next_number, 2);
    }
}
