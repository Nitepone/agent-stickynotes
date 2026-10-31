//! Agent-facing operations over the shared [`BoardStore`]. REST and MCP are
//! thin transports over this one service, so both behave identically.

use std::sync::Arc;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use chrono::{DateTime, Utc};
use rmcp::schemars::{self, JsonSchema};
use serde::{Deserialize, Serialize};
use stickynotes_core::{
    Applied, Artifact, ArtifactKind, Board, BoardStore, Column, Command, Criterion, CriterionDraft,
    Error, Origin, Progress, ReferenceDraft, Relation, Task, TaskDraft, TaskId, TaskPatch,
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

/// The user's project-level instructions for agents (read-only for agents).
#[derive(Debug, Serialize)]
pub struct ProjectView {
    pub title: String,
    /// How to write documents (specs, reports, release notes) for this project.
    pub document_prompt: String,
    /// How code for this project should be written.
    pub code_guidance: String,
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
    /// Short permanent number; refer to the task as "#<number>".
    pub number: u64,
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
    /// Short permanent number; refer to the task as "#<number>".
    pub number: u64,
    pub description: String,
    pub extended_description: String,
    pub requirements: Vec<String>,
    pub acceptance_criteria: Vec<CriterionView>,
    pub progress: Progress,
    pub references: Vec<ReferenceView>,
    pub artifacts: Vec<ArtifactView>,
    pub column: ColumnRef,
    /// The column `advance` would move this task into, with its entry criteria.
    pub next_column: Option<ColumnRef>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub revision: u64,
}

#[derive(Debug, Serialize)]
pub struct ReferenceView {
    /// The other task.
    pub task_id: Uuid,
    pub number: u64,
    /// What this task does to the other one: blocks, blocked_by, relates_to,
    /// duplicates or duplicated_by.
    pub relation: &'static str,
    pub description: String,
    pub column: String,
}

#[derive(Debug, Serialize)]
pub struct ArtifactView {
    pub id: Uuid,
    /// File name, as shown to the user.
    pub name: String,
    /// `markdown` or `image`.
    pub kind: &'static str,
    /// Where the file is, relative to the project folder.
    pub path: String,
    pub added_at: DateTime<Utc>,
    pub added_by_agent: bool,
}

/// An artifact with its text, when it has any.
#[derive(Debug, Serialize)]
pub struct ArtifactContent {
    #[serde(flatten)]
    pub artifact: ArtifactView,
    /// The file's text for Markdown and SVG; images are binary, so this is
    /// null for them and the file at `path` is the content.
    pub content: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ArtifactAdded {
    pub artifact: ArtifactView,
    pub revision: u64,
}

// Body of an add-artifact request. Give `content` for text, or
// `content_base64` for any file (needed for raster images).
//
// The input structs below also supply the MCP tool schemas, so their field doc
// comments are what agents read: keep them agent-facing.
#[derive(Debug, Deserialize, JsonSchema)]
pub struct NewArtifact {
    /// File name with extension: .md for Markdown, or .png .jpg .jpeg .gif
    /// .webp .svg for images. It is cleaned up and made unique, so check the
    /// returned name.
    pub name: String,
    /// The text, for .md and .svg files. Give this or content_base64.
    pub content: Option<String>,
    /// The file's bytes, base64 encoded (needed for raster images). Limits:
    /// 1 MiB for Markdown and SVG, 5 MiB for other images.
    pub content_base64: Option<String>,
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

// Body of a create request. Tasks always start in the first column.
#[derive(Debug, Deserialize, JsonSchema)]
pub struct NewTask {
    /// Short, sticky-note sized summary (about 200 characters suggested). Required.
    pub description: String,
    /// Longer free-form details.
    #[serde(default)]
    pub extended_description: String,
    #[serde(default)]
    pub requirements: Vec<String>,
    /// Acceptance criteria texts; they start unchecked.
    #[serde(default)]
    pub acceptance_criteria: Vec<String>,
}

// Body of an update request; omitted fields are unchanged.
#[derive(Debug, Default, Deserialize, JsonSchema)]
pub struct TaskUpdate {
    /// New short description (about 200 characters suggested).
    pub description: Option<String>,
    pub extended_description: Option<String>,
    /// Replaces the whole requirements list.
    pub requirements: Option<Vec<String>>,
    /// Replaces the whole criteria list. Pass existing ids to keep criteria.
    pub acceptance_criteria: Option<Vec<CriterionInput>>,
    /// Replaces all links to other tasks (pass the existing ones to keep
    /// them; omit the field to leave links alone). The other task gets the
    /// mirrored relation automatically.
    pub references: Option<Vec<ReferenceInput>>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(rename = "ReferenceArg")]
pub struct ReferenceInput {
    /// Id (or number such as #12) of the other task.
    pub task_id: String,
    /// What this task does to the other: blocks, blocked_by, relates_to,
    /// duplicates or duplicated_by.
    pub relation: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(rename = "CriterionArg")]
pub struct CriterionInput {
    /// Id of an existing criterion to keep (omit to add a new one).
    pub id: Option<String>,
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

    pub fn project(&self) -> ProjectView {
        self.store.read(|board, _| ProjectView {
            title: board.title.clone(),
            document_prompt: board.project.document_prompt.clone(),
            code_guidance: board.project.code_guidance.clone(),
        })
    }

    /// A task named by its id or by its number ("#12" or "12").
    fn resolve_task(&self, reference: &str) -> ServiceResult<Uuid> {
        let reference = reference.trim();
        if let Some(number) = parse_number(reference) {
            return self
                .store
                .read(|board, _| board.find_by_number(number).map(|t| t.id))
                .ok_or_else(|| Error::not_found("task", format!("#{number}")).into());
        }
        parse_id(reference, "task").map_err(|_| {
            ServiceError::BadRequest(format!(
                "'{reference}' is not a task id or number; use an id or a number like #12"
            ))
        })
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
        let id = self.resolve_task(id)?;
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
        let criteria = update
            .acceptance_criteria
            .map(|cs| {
                cs.into_iter()
                    .map(|c| {
                        Ok(CriterionDraft {
                            id: c
                                .id
                                .as_deref()
                                .map(|id| parse_id(id, "criterion"))
                                .transpose()?,
                            text: c.text,
                            done: c.done,
                        })
                    })
                    .collect::<ServiceResult<Vec<_>>>()
            })
            .transpose()?;
        let id = self.resolve_task(id)?;
        let references = update
            .references
            .map(|refs| {
                refs.into_iter()
                    .map(|r| {
                        Ok(ReferenceDraft {
                            task: self.resolve_task(&r.task_id)?,
                            relation: parse_relation(&r.relation)?,
                        })
                    })
                    .collect::<ServiceResult<Vec<_>>>()
            })
            .transpose()?;
        let patch = TaskPatch {
            description: update.description,
            extended_description: update.extended_description,
            requirements: update.requirements,
            acceptance_criteria: criteria,
            references,
        };
        self.apply_to_task(Command::UpdateTask { id, patch }, expected)
    }

    pub fn advance_task(&self, id: &str, expected: Option<u64>) -> ServiceResult<TaskView> {
        let id = self.resolve_task(id)?;
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
            task: self.resolve_task(task)?,
            criterion: parse_id(criterion, "criterion")?,
            done,
        };
        self.apply_to_task(cmd, expected)
    }

    pub fn add_artifact(
        &self,
        task: &str,
        new: NewArtifact,
        expected: Option<u64>,
    ) -> ServiceResult<ArtifactAdded> {
        let task = self.resolve_task(task)?;
        let data = match (new.content, new.content_base64) {
            (Some(text), None) => text.into_bytes(),
            (None, Some(b64)) => BASE64.decode(b64.trim()).map_err(|_| {
                ServiceError::BadRequest("content_base64 is not valid base64".into())
            })?,
            _ => {
                return Err(ServiceError::BadRequest(
                    "give exactly one of content (text) or content_base64".into(),
                ));
            }
        };
        let (artifact, revision) =
            self.store
                .add_artifact(Origin::Agent, task, &new.name, &data, expected)?;
        Ok(ArtifactAdded {
            artifact: artifact_view(&artifact),
            revision,
        })
    }

    /// An artifact of a task, named by its id or file name.
    pub fn artifact(&self, task: &str, artifact: &str) -> ServiceResult<ArtifactContent> {
        let task = self.resolve_task(task)?;
        let found = self.find_artifact(task, artifact)?;
        let content = match found.kind {
            ArtifactKind::Markdown => Some(self.read_text(&found)?),
            ArtifactKind::Image if found.name.ends_with(".svg") => Some(self.read_text(&found)?),
            ArtifactKind::Image => None,
        };
        Ok(ArtifactContent {
            artifact: artifact_view(&found),
            content,
        })
    }

    pub fn detach_artifact(
        &self,
        task: &str,
        artifact: &str,
        expected: Option<u64>,
    ) -> ServiceResult<TaskView> {
        let task = self.resolve_task(task)?;
        let artifact = self.find_artifact(task, artifact)?.id;
        self.apply_to_task(Command::DetachArtifact { task, artifact }, expected)
    }

    fn find_artifact(&self, task: Uuid, reference: &str) -> ServiceResult<Artifact> {
        let reference = reference.trim();
        let id = Uuid::parse_str(reference).ok();
        self.store.read(|board, _| {
            let t = board
                .task(task)
                .ok_or_else(|| Error::not_found("task", task))?;
            t.artifacts
                .iter()
                .find(|a| Some(a.id) == id || a.name == reference)
                .cloned()
                .ok_or_else(|| Error::not_found("artifact", reference).into())
        })
    }

    fn read_text(&self, artifact: &Artifact) -> ServiceResult<String> {
        let bytes = self.store.read_artifact(&artifact.name)?;
        String::from_utf8(bytes)
            .map_err(|_| ServiceError::BadRequest("the file is not valid UTF-8 text".into()))
    }

    pub fn delete_task(&self, id: &str, expected: Option<u64>) -> ServiceResult<Deleted> {
        let id = self.resolve_task(id)?;
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
        number: task.number,
        column: column.title.clone(),
        description: task.description.clone(),
        progress: task.progress(),
    }
}

fn artifact_view(a: &Artifact) -> ArtifactView {
    ArtifactView {
        id: a.id,
        name: a.name.clone(),
        kind: a.kind.as_str(),
        path: format!("{}/{}", stickynotes_core::project::ARTIFACTS_DIR, a.name),
        added_at: a.added_at,
        added_by_agent: a.by_agent,
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
    let (ci, ti) = board
        .locate_task(id)
        .ok_or_else(|| Error::not_found("task", id))?;
    let column = &board.columns[ci];
    let t = &column.tasks[ti];
    Ok(TaskView {
        id: t.id,
        number: t.number,
        description: t.description.clone(),
        extended_description: t.extended_description.clone(),
        requirements: t.requirements.clone(),
        acceptance_criteria: t.acceptance_criteria.iter().map(criterion_view).collect(),
        progress: t.progress(),
        references: t
            .references
            .iter()
            .filter_map(|r| {
                let (oc, ot) = board.locate_task(r.task)?;
                Some(ReferenceView {
                    task_id: r.task,
                    number: board.columns[oc].tasks[ot].number,
                    relation: r.relation.as_str(),
                    description: board.columns[oc].tasks[ot].description.clone(),
                    column: board.columns[oc].title.clone(),
                })
            })
            .collect(),
        artifacts: t.artifacts.iter().map(artifact_view).collect(),
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

fn parse_relation(s: &str) -> ServiceResult<Relation> {
    Relation::parse(s).ok_or_else(|| {
        ServiceError::BadRequest(format!(
            "'{s}' is not a relation; use one of: {}",
            Relation::ALL.map(Relation::as_str).join(", ")
        ))
    })
}

/// "#12" or "12" (but not an id) as a task number.
fn parse_number(s: &str) -> Option<u64> {
    s.strip_prefix('#').unwrap_or(s).trim().parse().ok()
}
