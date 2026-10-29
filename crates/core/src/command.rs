//! Commands are the only way to mutate a board. Both the UI controller and the
//! agent API build commands and hand them to [`crate::BoardStore::apply`].

use serde::Deserialize;

use crate::model::{ColumnId, CriterionId, Relation, TaskId};

/// Who issued a command. Agents are subject to extra rules.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Origin {
    User,
    Agent,
}

/// Content for a new task.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct TaskDraft {
    pub description: String,
    #[serde(default)]
    pub extended_description: String,
    #[serde(default)]
    pub requirements: Vec<String>,
    #[serde(default)]
    pub acceptance_criteria: Vec<CriterionDraft>,
}

/// An acceptance criterion as supplied by a client. An `id` matching an
/// existing criterion keeps that criterion's identity.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct CriterionDraft {
    #[serde(default)]
    pub id: Option<CriterionId>,
    pub text: String,
    #[serde(default)]
    pub done: bool,
}

/// A requested link from the task being edited to another task.
#[derive(Debug, Clone, Deserialize)]
pub struct ReferenceDraft {
    pub task: TaskId,
    pub relation: Relation,
}

/// Partial task update; `None` fields are left untouched.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct TaskPatch {
    pub description: Option<String>,
    pub extended_description: Option<String>,
    pub requirements: Option<Vec<String>>,
    pub acceptance_criteria: Option<Vec<CriterionDraft>>,
    /// Replaces the task's whole set of references. Mirrors on the other
    /// tasks are added and removed to match.
    pub references: Option<Vec<ReferenceDraft>>,
}

#[derive(Debug, Clone)]
pub enum Command {
    /// `column: None` means the first column; `position: None` means the end.
    CreateTask {
        column: Option<ColumnId>,
        position: Option<usize>,
        draft: TaskDraft,
    },
    UpdateTask {
        id: TaskId,
        patch: TaskPatch,
    },
    MoveTask {
        id: TaskId,
        to_column: ColumnId,
        position: Option<usize>,
    },
    /// Move a task to the end of the next column to the right.
    AdvanceTask {
        id: TaskId,
    },
    DeleteTask {
        id: TaskId,
    },
    SetCriterion {
        task: TaskId,
        criterion: CriterionId,
        done: bool,
    },
    CreateColumn {
        position: Option<usize>,
        title: String,
        description: String,
    },
    UpdateColumn {
        id: ColumnId,
        title: Option<String>,
        description: Option<String>,
    },
    MoveColumn {
        id: ColumnId,
        position: usize,
    },
    DeleteColumn {
        id: ColumnId,
        force: bool,
    },
    RenameBoard {
        title: String,
    },
    /// `None` fields are left untouched.
    UpdateProject {
        document_prompt: Option<String>,
        code_guidance: Option<String>,
    },
}

/// What a successfully applied command produced.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Applied {
    Task(TaskId),
    Column(ColumnId),
    Board,
}
