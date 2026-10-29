//! Agent-facing operations over the shared [`BoardStore`]. REST and MCP are
//! thin transports over this one service, so both behave identically.

use std::sync::Arc;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use stickynotes_core::{
    Applied, Board, BoardStore, Column, Command, Criterion, CriterionDraft, Error, Origin,
    Progress, Task, TaskDraft, TaskId, TaskPatch,
};
use uuid::Uuid;

/// Errors surfaced to agents.
#[derive(Debug)]
pub enum ServiceError {
    Core(Error),
    BadRequest(String),
}

impl From<Error> for ServiceError {
    fn from(e: Error) -> Self {
        ServiceError::Core(e)
    }
}

impl std::fmt::Display for ServiceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ServiceError::Core(e) => e.fmt(f),
            ServiceError::BadRequest(m) => f.write_str(m),
        }
    }
}

pub type ServiceResult<T> = Result<T, ServiceError>;

#[derive(Debug, Serialize)]
pub struct BoardView {
    pub title: String,
    pub revision: u64,
    pub agent_write: bool,
    pub columns: Vec<ColumnView>,
}

#[derive(Debug, Serialize)]
pub struct ColumnView {
    pub id: Uuid,
    pub position: usize,
    pub title: String,
    pub description: String,
    pub tasks: Vec<TaskSummary>,
}

#[derive(Debug, Serialize)]
pub struct TaskSummary {
    pub id: Uuid,
    pub column: String,
    pub description: String,
    pub progress: Progress,
}

#[derive(Debug, Serialize)]
pub struct ColumnRef {
    pub id: Uuid,
    pub title: String,
    pub description: String,
}

#[derive(Debug, Serialize)]
pub struct TaskView {
    pub id: Uuid,
    pub description: String,
    pub extended_description: String,
    pub requirements: Vec<String>,
    pub acceptance_criteria: Vec<CriterionView>,
    pub progress: Progress,
    pub column: ColumnRef,
    /// The column `advance` would move this task into, with its entry criteria.
    pub next_column: Option<ColumnRef>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub revision: u64,
}

#[derive(Debug, Serialize)]
pub struct CriterionView {
    pub id: Uuid,
    pub text: String,
    pub done: bool,
}

#[derive(Debug, Serialize)]
pub struct Deleted {
    pub deleted: Uuid,
    pub revision: u64,
}

/// Body of a create request. Tasks always start in the first column.
#[derive(Debug, Deserialize)]
pub struct NewTask {
    pub description: String,
    #[serde(default)]
    pub extended_description: String,
    #[serde(default)]
    pub requirements: Vec<String>,
    /// Plain criterion texts; new criteria start unchecked.
    #[serde(default)]
    pub acceptance_criteria: Vec<String>,
}

/// Body of an update request; omitted fields are unchanged.
#[derive(Debug, Default, Deserialize)]
pub struct TaskUpdate {
    pub description: Option<String>,
    pub extended_description: Option<String>,
    pub requirements: Option<Vec<String>>,
    pub acceptance_criteria: Option<Vec<CriterionInput>>,
}

#[derive(Debug, Deserialize)]
pub struct CriterionInput {
    /// Id of an existing criterion to keep; omit for a new one.
    pub id: Option<Uuid>,
    pub text: String,
    #[serde(default)]
    pub done: bool,
}

#[derive(Clone)]
pub struct AgentService {
    store: Arc<BoardStore>,
}

impl AgentService {
    pub fn new(store: Arc<BoardStore>) -> Self {
        AgentService { store }
    }

    pub fn board(&self) -> BoardView {
        let snapshot = self.store.snapshot();
        let (board, revision) = (&snapshot.board, snapshot.revision);
        BoardView {
            title: board.title.clone(),
            revision,
            agent_write: snapshot.agent_write,
            columns: board
                .columns
                .iter()
                .enumerate()
                .map(|(position, c)| ColumnView {
                    id: c.id,
                    position,
                    title: c.title.clone(),
                    description: c.description.clone(),
                    tasks: c.tasks.iter().map(|t| summary(c, t)).collect(),
                })
                .collect(),
        }
    }

    pub fn markdown(&self) -> String {
        self.store.to_markdown()
    }

    /// Task summaries, optionally filtered by column id or title.
    pub fn list_tasks(&self, column: Option<&str>) -> ServiceResult<Vec<TaskSummary>> {
        self.store.read(|board, _| {
            let filter = column.map(|c| resolve_column(board, c)).transpose()?;
            Ok(board
                .tasks()
                .filter(|(c, _)| filter.is_none_or(|id| c.id == id))
                .map(|(c, t)| summary(c, t))
                .collect())
        })
    }

    pub fn task(&self, id: &str) -> ServiceResult<TaskView> {
        let id = parse_id(id, "task")?;
        self.store
            .read(|board, revision| task_view(board, id, revision))
    }

    pub fn create_task(&self, new: NewTask, expected: Option<u64>) -> ServiceResult<TaskView> {
        let draft = TaskDraft {
            description: new.description,
            extended_description: new.extended_description,
            requirements: new.requirements,
            acceptance_criteria: new
                .acceptance_criteria
                .into_iter()
                .map(|text| CriterionDraft {
                    text,
                    ..Default::default()
                })
                .collect(),
        };
        self.apply_to_task(
            Command::CreateTask {
                column: None,
                position: None,
                draft,
            },
            expected,
        )
    }

    pub fn update_task(
        &self,
        id: &str,
        update: TaskUpdate,
        expected: Option<u64>,
    ) -> ServiceResult<TaskView> {
        let id = parse_id(id, "task")?;
        let patch = TaskPatch {
            description: update.description,
            extended_description: update.extended_description,
            requirements: update.requirements,
            acceptance_criteria: update.acceptance_criteria.map(|cs| {
                cs.into_iter()
                    .map(|c| CriterionDraft {
                        id: c.id,
                        text: c.text,
                        done: c.done,
                    })
                    .collect()
            }),
        };
        self.apply_to_task(Command::UpdateTask { id, patch }, expected)
    }

    pub fn advance_task(&self, id: &str, expected: Option<u64>) -> ServiceResult<TaskView> {
        let id = parse_id(id, "task")?;
        self.apply_to_task(Command::AdvanceTask { id }, expected)
    }

    pub fn set_criterion(
        &self,
        task: &str,
        criterion: &str,
        done: bool,
        expected: Option<u64>,
    ) -> ServiceResult<TaskView> {
        let cmd = Command::SetCriterion {
            task: parse_id(task, "task")?,
            criterion: parse_id(criterion, "criterion")?,
            done,
        };
        self.apply_to_task(cmd, expected)
    }

    pub fn delete_task(&self, id: &str, expected: Option<u64>) -> ServiceResult<Deleted> {
        let id = parse_id(id, "task")?;
        let (_, revision) =
            self.store
                .apply(Origin::Agent, Command::DeleteTask { id }, expected)?;
        Ok(Deleted {
            deleted: id,
            revision,
        })
    }

    fn apply_to_task(&self, cmd: Command, expected: Option<u64>) -> ServiceResult<TaskView> {
        let (applied, _) = self.store.apply(Origin::Agent, cmd, expected)?;
        let Applied::Task(id) = applied else {
            unreachable!("task commands produce tasks")
        };
        self.store
            .read(|board, revision| task_view(board, id, revision))
    }
}

fn summary(column: &Column, task: &Task) -> TaskSummary {
    TaskSummary {
        id: task.id,
        column: column.title.clone(),
        description: task.description.clone(),
        progress: task.progress(),
    }
}

fn column_ref(c: &Column) -> ColumnRef {
    ColumnRef {
        id: c.id,
        title: c.title.clone(),
        description: c.description.clone(),
    }
}

fn criterion_view(c: &Criterion) -> CriterionView {
    CriterionView {
        id: c.id,
        text: c.text.clone(),
        done: c.done,
    }
}

fn task_view(board: &Board, id: TaskId, revision: u64) -> ServiceResult<TaskView> {
    let (ci, ti) = board.locate_task(id).ok_or_else(|| Error::NotFound {
        kind: "task",
        id: id.to_string(),
    })?;
    let column = &board.columns[ci];
    let t = &column.tasks[ti];
    Ok(TaskView {
        id: t.id,
        description: t.description.clone(),
        extended_description: t.extended_description.clone(),
        requirements: t.requirements.clone(),
        acceptance_criteria: t.acceptance_criteria.iter().map(criterion_view).collect(),
        progress: t.progress(),
        column: column_ref(column),
        next_column: board.columns.get(ci + 1).map(column_ref),
        created_at: t.created_at,
        updated_at: t.updated_at,
        revision,
    })
}

/// Accept a column id or a case-insensitive exact title.
fn resolve_column(board: &Board, reference: &str) -> ServiceResult<Uuid> {
    if let Ok(id) = Uuid::parse_str(reference)
        && board.column_index(id).is_some()
    {
        return Ok(id);
    }
    let matches: Vec<_> = board
        .columns
        .iter()
        .filter(|c| c.title.eq_ignore_ascii_case(reference.trim()))
        .collect();
    match matches.as_slice() {
        [c] => Ok(c.id),
        [] => Err(ServiceError::BadRequest(format!(
            "no column matches '{reference}'; columns are: {}",
            column_titles(board)
        ))),
        _ => Err(ServiceError::BadRequest(format!(
            "'{reference}' matches several columns; use one of the ids: {}",
            matches
                .iter()
                .map(|c| c.id.to_string())
                .collect::<Vec<_>>()
                .join(", ")
        ))),
    }
}

fn column_titles(board: &Board) -> String {
    board
        .columns
        .iter()
        .map(|c| c.title.as_str())
        .collect::<Vec<_>>()
        .join(", ")
}

fn parse_id(s: &str, kind: &str) -> ServiceResult<Uuid> {
    Uuid::parse_str(s.trim())
        .map_err(|_| ServiceError::BadRequest(format!("'{s}' is not a valid {kind} id")))
}
