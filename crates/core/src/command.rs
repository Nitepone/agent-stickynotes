//! Commands are the only way to mutate a board. Both the UI controller and the
//! agent API build commands and hand them to [`crate::BoardStore::apply`].

use crate::model::{Artifact, ArtifactId, ColumnId, CriterionId, Relation, TaskId};

/// Who issued a command. Agents are subject to extra rules.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Origin {
    User,
    Agent,
}

/// Content for a new task.
#[derive(Debug, Clone, Default)]
pub struct TaskDraft {
    pub description: String,
    pub extended_description: String,
    pub requirements: Vec<String>,
    pub acceptance_criteria: Vec<CriterionDraft>,
    /// Blank means uncategorized. Matched case-insensitively against the
    /// categories already on the board.
    pub category: Option<String>,
}

/// An acceptance criterion as supplied by a client. An `id` matching an
/// existing criterion keeps that criterion's identity.
#[derive(Debug, Clone, Default)]
pub struct CriterionDraft {
    pub id: Option<CriterionId>,
    pub text: String,
    pub done: bool,
}

/// A requested link from the task being edited to another task.
#[derive(Debug, Clone)]
pub struct ReferenceDraft {
    pub task: TaskId,
    pub relation: Relation,
}

/// Partial task update; `None` fields are left untouched.
#[derive(Debug, Clone, Default)]
pub struct TaskPatch {
    pub description: Option<String>,
    pub extended_description: Option<String>,
    pub requirements: Option<Vec<String>>,
    pub acceptance_criteria: Option<Vec<CriterionDraft>>,
    /// Replaces the task's whole set of references. Mirrors on the other
    /// tasks are added and removed to match.
    pub references: Option<Vec<ReferenceDraft>>,
    /// `Some("")` (or blanks) clears the category; `None` leaves it alone.
    pub category: Option<String>,
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
    /// User only. Move several tasks, in the order given, to `to_column`, as one
    /// contiguous run at `position` (an index into the target column's tasks
    /// once the moved ones are removed; at most that length). All or none.
    MoveTasks {
        ids: Vec<TaskId>,
        to_column: ColumnId,
        position: usize,
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
    /// Record a file already written to `artifacts/` on a task. The task's
    /// current column title is stored as the artifact's stage, and `added_by`
    /// (the caller's name) as who added it; any values already on `artifact`
    /// are overwritten.
    AttachArtifact {
        task: TaskId,
        artifact: Artifact,
        added_by: Option<String>,
    },
    /// Remove the record from the task; the file stays in `artifacts/`.
    DetachArtifact {
        task: TaskId,
        artifact: ArtifactId,
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
    /// Put entities back as they were (undo and redo). Built by the store
    /// only; agents are refused it.
    Restore(Box<crate::history::Snap>),
}

/// What a successfully applied command produced.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Applied {
    Task(TaskId),
    Column(ColumnId),
    Board,
}
