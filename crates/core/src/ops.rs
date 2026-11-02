//! Pure command execution against a [`Board`]. No locking, no I/O.

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde_json::Map;
use uuid::Uuid;

use crate::command::{
    Applied, Command, CriterionDraft, Origin, ReferenceDraft, TaskDraft, TaskPatch,
};
use crate::error::{Error, Result};
use crate::model::{
    AgentChange, Board, ChangeKind, Column, ColumnId, Criterion, Reference, Task, TaskId,
};

/// Validate and apply `cmd` to `board`. On error the board is unchanged.
pub fn execute(board: &mut Board, origin: Origin, cmd: Command) -> Result<Applied> {
    if origin == Origin::Agent {
        check_agent_rules(board, &cmd)?;
    }
    if let Command::Restore(snap) = &cmd {
        // A restore puts back exact copies, agent markers included.
        crate::history::restore(board, snap)?;
        return Ok(Applied::Board);
    }
    let kind = change_kind(&cmd);
    let before = update_stamps(board);
    let applied = run(board, cmd)?;
    track_changes(board, origin, kind, &applied, &before);
    Ok(applied)
}

/// How a command changes the task it targets, for the agent-change marker.
fn change_kind(cmd: &Command) -> ChangeKind {
    match cmd {
        Command::CreateTask { .. } => ChangeKind::Created,
        Command::MoveTask { .. } | Command::MoveTasks { .. } | Command::AdvanceTask { .. } => {
            ChangeKind::Moved
        }
        Command::SetCriterion { .. } => ChangeKind::Progress,
        _ => ChangeKind::Edited,
    }
}

fn update_stamps(board: &Board) -> HashMap<TaskId, DateTime<Utc>> {
    board.tasks().map(|(_, t)| (t.id, t.updated_at)).collect()
}

/// Mark every task the command touched: by an agent, so the UI can highlight
/// it; by the user, which clears the mark (they have seen it). Tasks changed
/// only as a side effect (the other end of a link) count as edited.
fn track_changes(
    board: &mut Board,
    origin: Origin,
    kind: ChangeKind,
    applied: &Applied,
    before: &HashMap<TaskId, DateTime<Utc>>,
) {
    let target = match applied {
        Applied::Task(id) => Some(*id),
        _ => None,
    };
    for column in &mut board.columns {
        for task in &mut column.tasks {
            if before.get(&task.id) == Some(&task.updated_at) {
                continue;
            }
            task.agent_change = match origin {
                Origin::Agent => Some(AgentChange {
                    at: task.updated_at,
                    kind: if target == Some(task.id) {
                        kind
                    } else {
                        ChangeKind::Edited
                    },
                    extra: Map::new(),
                }),
                Origin::User => None,
            };
        }
    }
}

fn run(board: &mut Board, cmd: Command) -> Result<Applied> {
    match cmd {
        Command::CreateTask {
            column,
            position,
            draft,
        } => create_task(board, column, position, draft),
        Command::UpdateTask { id, patch } => update_task(board, id, patch),
        Command::MoveTask {
            id,
            to_column,
            position,
        } => move_task(board, id, to_column, position),
        Command::MoveTasks {
            ids,
            to_column,
            position,
        } => move_tasks(board, &ids, to_column, position),
        Command::AdvanceTask { id } => {
            let (ci, _) = locate(board, id)?;
            let next = board
                .columns
                .get(ci + 1)
                .ok_or_else(|| Error::Validation("task is already in the last column".into()))?
                .id;
            move_task(board, id, next, None)
        }
        Command::DeleteTask { id } => {
            let (ci, ti) = locate(board, id)?;
            board.columns[ci].tasks.remove(ti);
            remove_references_to(board, &[id]);
            Ok(Applied::Task(id))
        }
        Command::SetCriterion {
            task,
            criterion,
            done,
        } => {
            let t = task_mut(board, task)?;
            let c = t
                .acceptance_criteria
                .iter_mut()
                .find(|c| c.id == criterion)
                .ok_or_else(|| not_found("criterion", criterion))?;
            if c.done != done {
                c.done = done;
                t.updated_at = Utc::now();
            }
            Ok(Applied::Task(task))
        }
        Command::AttachArtifact { task, artifact } => {
            let t = task_mut(board, task)?;
            if t.artifacts.len() >= crate::artifact::MAX_PER_TASK {
                return Err(Error::Validation(format!(
                    "a task can have at most {} artifacts; detach one first",
                    crate::artifact::MAX_PER_TASK
                )));
            }
            if t.artifacts
                .iter()
                .any(|a| a.id == artifact.id || a.name == artifact.name)
            {
                return Err(Error::Validation(format!(
                    "'{}' is already attached to this task",
                    artifact.name
                )));
            }
            t.artifacts.push(artifact);
            t.updated_at = Utc::now();
            Ok(Applied::Task(task))
        }
        Command::DetachArtifact { task, artifact } => {
            let t = task_mut(board, task)?;
            let at = t
                .artifacts
                .iter()
                .position(|a| a.id == artifact)
                .ok_or_else(|| not_found("artifact", artifact))?;
            t.artifacts.remove(at);
            t.updated_at = Utc::now();
            Ok(Applied::Task(task))
        }
        Command::CreateColumn {
            position,
            title,
            description,
        } => {
            let column = Column::new(required(&title, "column title")?, description.trim());
            let id = column.id;
            let pos = clamp(position, board.columns.len());
            board.columns.insert(pos, column);
            Ok(Applied::Column(id))
        }
        Command::UpdateColumn {
            id,
            title,
            description,
        } => {
            let title = title.map(|t| required(&t, "column title")).transpose()?;
            let col = column_mut(board, id)?;
            if let Some(title) = title {
                col.title = title;
            }
            if let Some(description) = description {
                col.description = description.trim().to_string();
            }
            Ok(Applied::Column(id))
        }
        Command::MoveColumn { id, position } => {
            let from = column_index(board, id)?;
            let col = board.columns.remove(from);
            let to = position.min(board.columns.len());
            board.columns.insert(to, col);
            Ok(Applied::Column(id))
        }
        Command::DeleteColumn { id, force } => {
            let idx = column_index(board, id)?;
            let col = &board.columns[idx];
            if !col.tasks.is_empty() && !force {
                return Err(Error::ColumnNotEmpty(col.title.clone()));
            }
            let removed = board.columns.remove(idx);
            let ids: Vec<_> = removed.tasks.iter().map(|t| t.id).collect();
            remove_references_to(board, &ids);
            Ok(Applied::Column(id))
        }
        Command::RenameBoard { title } => {
            board.title = required(&title, "board title")?;
            Ok(Applied::Board)
        }
        Command::UpdateProject {
            document_prompt,
            code_guidance,
        } => {
            if let Some(p) = document_prompt {
                board.project.document_prompt = p.trim().to_string();
            }
            if let Some(g) = code_guidance {
                board.project.code_guidance = g.trim().to_string();
            }
            Ok(Applied::Board)
        }
        Command::Restore(snap) => {
            crate::history::restore(board, &snap)?;
            Ok(Applied::Board)
        }
    }
}

/// Agents may only touch tasks, may only create in the first column, and may
/// only move a task one column to the right.
fn check_agent_rules(board: &Board, cmd: &Command) -> Result<()> {
    let deny = |msg: &str| Err(Error::AgentNotPermitted(msg.into()));
    match cmd {
        Command::CreateTask { column, .. } => match (column, board.columns.first()) {
            (Some(col), Some(first)) if *col != first.id => {
                deny("agents can only create tasks in the first column")
            }
            _ => Ok(()),
        },
        Command::MoveTask { id, to_column, .. } => {
            let (from, _) = locate(board, *id)?;
            let to = column_index(board, *to_column)?;
            if to == from + 1 {
                Ok(())
            } else {
                deny("agents can only move a task to the next column on the right")
            }
        }
        Command::CreateColumn { .. }
        | Command::UpdateColumn { .. }
        | Command::MoveColumn { .. }
        | Command::DeleteColumn { .. }
        | Command::RenameBoard { .. } => deny("agents cannot modify columns or the board"),
        Command::UpdateProject { .. } => deny("only the user can edit project settings"),
        Command::Restore(_) => deny("agents cannot undo or redo"),
        Command::MoveTasks { .. } => deny("agents move one task at a time, one column right"),
        Command::UpdateTask { .. }
        | Command::AdvanceTask { .. }
        | Command::DeleteTask { .. }
        | Command::SetCriterion { .. }
        | Command::AttachArtifact { .. }
        | Command::DetachArtifact { .. } => Ok(()),
    }
}

fn create_task(
    board: &mut Board,
    column: Option<ColumnId>,
    position: Option<usize>,
    draft: TaskDraft,
) -> Result<Applied> {
    let ci = match column {
        Some(id) => column_index(board, id)?,
        None if board.columns.is_empty() => {
            return Err(Error::Validation("the board has no columns".into()));
        }
        None => 0,
    };
    let category = normalize_category(board, draft.category.as_deref())?;
    let now = Utc::now();
    let task = Task {
        id: Uuid::new_v4(),
        number: board.take_number(),
        description: required(&draft.description, "task description")?,
        extended_description: draft.extended_description.trim().to_string(),
        requirements: clean_lines(draft.requirements),
        acceptance_criteria: merge_criteria(&[], draft.acceptance_criteria),
        references: Vec::new(),
        artifacts: Vec::new(),
        category,
        agent_change: None,
        created_at: now,
        updated_at: now,
        extra: Map::new(),
    };
    let id = task.id;
    let tasks = &mut board.columns[ci].tasks;
    let pos = clamp(position, tasks.len());
    tasks.insert(pos, task);
    Ok(Applied::Task(id))
}

fn update_task(board: &mut Board, id: TaskId, patch: TaskPatch) -> Result<Applied> {
    // Validate everything before changing anything.
    let description = patch
        .description
        .map(|d| required(&d, "task description"))
        .transpose()?;
    locate(board, id)?;
    let category = patch
        .category
        .as_deref()
        .map(|c| normalize_category(board, Some(c)))
        .transpose()?;
    let references = patch
        .references
        .map(|drafts| normalize_references(board, id, drafts))
        .transpose()?;

    let task = task_mut(board, id)?;
    if let Some(d) = description {
        task.description = d;
    }
    if let Some(d) = patch.extended_description {
        task.extended_description = d.trim().to_string();
    }
    if let Some(r) = patch.requirements {
        task.requirements = clean_lines(r);
    }
    if let Some(c) = patch.acceptance_criteria {
        task.acceptance_criteria = merge_criteria(&task.acceptance_criteria, c);
    }
    if let Some(c) = category {
        task.category = c;
    }
    task.updated_at = Utc::now();
    if let Some(references) = references {
        set_references(board, id, references);
    }
    Ok(Applied::Task(id))
}

/// Check that every target exists and is not the task itself; keep the last
/// relation given for a target.
fn normalize_references(
    board: &Board,
    id: TaskId,
    drafts: Vec<ReferenceDraft>,
) -> Result<Vec<(TaskId, crate::model::Relation)>> {
    let mut result: Vec<(TaskId, crate::model::Relation)> = Vec::new();
    for draft in drafts {
        if draft.task == id {
            return Err(Error::Validation("a task cannot reference itself".into()));
        }
        if board.task(draft.task).is_none() {
            return Err(not_found("task", draft.task));
        }
        result.retain(|(t, _)| *t != draft.task);
        result.push((draft.task, draft.relation));
    }
    Ok(result)
}

/// Make `id`'s references exactly `wanted`, mirroring every change onto the
/// other task. `wanted` must already be validated.
fn set_references(board: &mut Board, id: TaskId, wanted: Vec<(TaskId, crate::model::Relation)>) {
    let current: Vec<Reference> = board
        .task(id)
        .map(|t| t.references.clone())
        .unwrap_or_default();
    let now = Utc::now();

    // Drop links that are gone or changed, along with their mirrors.
    for old in &current {
        if wanted.contains(&(old.task, old.relation)) {
            continue;
        }
        if let Some(other) = board.task_mut(old.task) {
            other.references.retain(|r| r.task != id);
            other.updated_at = now;
        }
    }

    let mut kept = Vec::with_capacity(wanted.len());
    for (target, relation) in wanted {
        let existing = current
            .iter()
            .find(|r| r.task == target && r.relation == relation);
        kept.push(
            existing
                .cloned()
                .unwrap_or_else(|| Reference::new(target, relation)),
        );
        if existing.is_some() {
            continue;
        }
        if let Some(other) = board.task_mut(target) {
            other.references.retain(|r| r.task != id);
            other
                .references
                .push(Reference::new(id, relation.inverse()));
            other.updated_at = now;
        }
    }
    if let Some(task) = board.task_mut(id) {
        task.references = kept;
    }
}

/// Remove every reference that points at one of `gone`.
fn remove_references_to(board: &mut Board, gone: &[TaskId]) {
    let now = Utc::now();
    for column in &mut board.columns {
        for task in &mut column.tasks {
            let before = task.references.len();
            task.references.retain(|r| !gone.contains(&r.task));
            if task.references.len() != before {
                task.updated_at = now;
            }
        }
    }
}

fn move_task(
    board: &mut Board,
    id: TaskId,
    to_column: ColumnId,
    position: Option<usize>,
) -> Result<Applied> {
    let to = column_index(board, to_column)?;
    let (ci, ti) = locate(board, id)?;
    let mut task = board.columns[ci].tasks.remove(ti);
    task.updated_at = Utc::now();
    let tasks = &mut board.columns[to].tasks;
    let pos = clamp(position, tasks.len());
    tasks.insert(pos, task);
    Ok(Applied::Task(id))
}

/// Move `ids` (in that order) to `to_column` as a contiguous run at `position`.
/// Everything is validated before anything changes.
fn move_tasks(
    board: &mut Board,
    ids: &[TaskId],
    to_column: ColumnId,
    position: usize,
) -> Result<Applied> {
    let to = column_index(board, to_column)?;
    if ids.is_empty() {
        return Err(Error::Validation("no tasks to move".into()));
    }
    let mut seen = std::collections::HashSet::new();
    for id in ids {
        locate(board, *id)?;
        if !seen.insert(*id) {
            return Err(Error::Validation("a task is listed twice".into()));
        }
    }
    let remaining = board.columns[to]
        .tasks
        .iter()
        .filter(|t| !seen.contains(&t.id))
        .count();
    if position > remaining {
        return Err(Error::Validation(format!(
            "position {position} is past the end of the column ({remaining} tasks)"
        )));
    }
    let now = Utc::now();
    let mut moved = Vec::with_capacity(ids.len());
    for id in ids {
        let (ci, ti) = locate(board, *id)?;
        let mut task = board.columns[ci].tasks.remove(ti);
        task.updated_at = now;
        moved.push(task);
    }
    board.columns[to].tasks.splice(position..position, moved);
    Ok(Applied::Board)
}

/// Keep ids (and unknown fields) of criteria the client referenced by id.
fn merge_criteria(existing: &[Criterion], drafts: Vec<CriterionDraft>) -> Vec<Criterion> {
    drafts
        .into_iter()
        .filter_map(|d| {
            let text = d.text.trim().to_string();
            if text.is_empty() {
                return None;
            }
            let prior = d.id.and_then(|id| existing.iter().find(|c| c.id == id));
            Some(Criterion {
                id: prior.map_or_else(Uuid::new_v4, |c| c.id),
                text,
                done: d.done,
                extra: prior.map(|c| c.extra.clone()).unwrap_or_default(),
            })
        })
        .collect()
}

fn clean_lines(lines: Vec<String>) -> Vec<String> {
    lines
        .into_iter()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect()
}

/// Longest category name, in characters.
pub const MAX_CATEGORY_CHARS: usize = 40;

/// Trim a category; blank means none. A name that matches (ignoring case) a
/// category already used on the board takes that category's spelling, so the
/// board never holds near-duplicates.
fn normalize_category(board: &Board, raw: Option<&str>) -> Result<Option<String>> {
    let name = raw.unwrap_or("").trim();
    if name.is_empty() {
        return Ok(None);
    }
    if name.chars().count() > MAX_CATEGORY_CHARS {
        return Err(Error::Validation(format!(
            "category must be at most {MAX_CATEGORY_CHARS} characters"
        )));
    }
    let wanted = name.to_lowercase();
    let existing = board
        .tasks()
        .filter_map(|(_, t)| t.category.as_deref())
        .find(|c| c.to_lowercase() == wanted);
    Ok(Some(existing.unwrap_or(name).to_string()))
}

fn required(value: &str, what: &str) -> Result<String> {
    let v = value.trim();
    if v.is_empty() {
        Err(Error::Validation(format!("{what} must not be empty")))
    } else {
        Ok(v.to_string())
    }
}

fn clamp(position: Option<usize>, len: usize) -> usize {
    position.map_or(len, |p| p.min(len))
}

fn not_found(kind: &'static str, id: Uuid) -> Error {
    Error::not_found(kind, id)
}

fn locate(board: &Board, id: TaskId) -> Result<(usize, usize)> {
    board.locate_task(id).ok_or_else(|| not_found("task", id))
}

fn column_index(board: &Board, id: ColumnId) -> Result<usize> {
    board
        .column_index(id)
        .ok_or_else(|| not_found("column", id))
}

fn task_mut(board: &mut Board, id: TaskId) -> Result<&mut Task> {
    let (ci, ti) = locate(board, id)?;
    Ok(&mut board.columns[ci].tasks[ti])
}

fn column_mut(board: &mut Board, id: ColumnId) -> Result<&mut Column> {
    let idx = column_index(board, id)?;
    Ok(&mut board.columns[idx])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn draft(description: &str) -> TaskDraft {
        TaskDraft {
            description: description.into(),
            ..Default::default()
        }
    }

    fn board_with_task() -> (Board, TaskId) {
        let mut b = Board::new_default();
        let Applied::Task(id) = execute(
            &mut b,
            Origin::User,
            Command::CreateTask {
                column: None,
                position: None,
                draft: draft("first"),
            },
        )
        .unwrap() else {
            panic!()
        };
        (b, id)
    }

    fn col(b: &Board, i: usize) -> ColumnId {
        b.columns[i].id
    }

    fn task_count(b: &Board) -> usize {
        b.columns.iter().map(|c| c.tasks.len()).sum()
    }

    #[test]
    fn create_defaults_to_first_column_end() {
        let (mut b, first) = board_with_task();
        let cmd = Command::CreateTask {
            column: None,
            position: None,
            draft: draft("second"),
        };
        execute(&mut b, Origin::User, cmd).unwrap();
        assert_eq!(b.columns[0].tasks[0].id, first);
        assert_eq!(b.columns[0].tasks[1].description, "second");
    }

    fn cat_task(b: &mut Board, origin: Origin, category: Option<&str>) -> Result<TaskId> {
        match execute(
            b,
            origin,
            Command::CreateTask {
                column: None,
                position: None,
                draft: TaskDraft {
                    description: "t".into(),
                    category: category.map(String::from),
                    ..Default::default()
                },
            },
        )? {
            Applied::Task(id) => Ok(id),
            _ => unreachable!(),
        }
    }

    fn set_cat(b: &mut Board, id: TaskId, c: &str) -> Result<Applied> {
        execute(
            b,
            Origin::User,
            Command::UpdateTask {
                id,
                patch: TaskPatch {
                    category: Some(c.into()),
                    ..Default::default()
                },
            },
        )
    }

    #[test]
    fn category_is_trimmed_and_matched_case_insensitively() {
        let mut b = Board::new_default();
        let a = cat_task(&mut b, Origin::User, Some("  UI ")).unwrap();
        let c = cat_task(&mut b, Origin::Agent, Some("ui")).unwrap();
        let d = cat_task(&mut b, Origin::User, None).unwrap();
        assert_eq!(b.task(a).unwrap().category.as_deref(), Some("UI"));
        assert_eq!(b.task(c).unwrap().category.as_deref(), Some("UI"));
        assert_eq!(b.task(d).unwrap().category, None);
        set_cat(&mut b, d, "uI").unwrap();
        assert_eq!(b.task(d).unwrap().category.as_deref(), Some("UI"));
        set_cat(&mut b, d, "Backend").unwrap();
        assert_eq!(b.task(d).unwrap().category.as_deref(), Some("Backend"));
    }

    #[test]
    fn blank_category_clears_and_none_keeps() {
        let mut b = Board::new_default();
        let a = cat_task(&mut b, Origin::User, Some("UI")).unwrap();
        execute(
            &mut b,
            Origin::User,
            Command::UpdateTask {
                id: a,
                patch: TaskPatch {
                    description: Some("x".into()),
                    ..Default::default()
                },
            },
        )
        .unwrap();
        assert_eq!(b.task(a).unwrap().category.as_deref(), Some("UI"));
        set_cat(&mut b, a, "   ").unwrap();
        assert_eq!(b.task(a).unwrap().category, None);
        // Once unused, the spelling is free again.
        set_cat(&mut b, a, "ui").unwrap();
        assert_eq!(b.task(a).unwrap().category.as_deref(), Some("ui"));
    }

    #[test]
    fn too_long_category_is_rejected_and_board_unchanged() {
        let mut b = Board::new_default();
        let a = cat_task(&mut b, Origin::User, Some("UI")).unwrap();
        let long = "x".repeat(MAX_CATEGORY_CHARS + 1);
        assert!(matches!(
            set_cat(&mut b, a, &long),
            Err(Error::Validation(_))
        ));
        assert!(cat_task(&mut b, Origin::User, Some(&long)).is_err());
        assert_eq!(b.task(a).unwrap().category.as_deref(), Some("UI"));
        assert!(set_cat(&mut b, a, &"x".repeat(MAX_CATEGORY_CHARS)).is_ok());
    }

    #[test]
    fn create_requires_description() {
        let mut b = Board::new_default();
        let cmd = Command::CreateTask {
            column: None,
            position: None,
            draft: draft("   "),
        };
        assert!(matches!(
            execute(&mut b, Origin::User, cmd),
            Err(Error::Validation(_))
        ));
        assert_eq!(task_count(&b), 0);
    }

    #[test]
    fn create_cleans_blank_requirements_and_criteria() {
        let mut b = Board::new_default();
        let cmd = Command::CreateTask {
            column: None,
            position: None,
            draft: TaskDraft {
                description: "d".into(),
                requirements: vec![" a ".into(), "".into()],
                acceptance_criteria: vec![
                    CriterionDraft {
                        text: "x".into(),
                        ..Default::default()
                    },
                    CriterionDraft {
                        text: " ".into(),
                        ..Default::default()
                    },
                ],
                ..Default::default()
            },
        };
        execute(&mut b, Origin::User, cmd).unwrap();
        let t = &b.columns[0].tasks[0];
        assert_eq!(t.requirements, vec!["a"]);
        assert_eq!(t.acceptance_criteria.len(), 1);
    }

    #[test]
    fn long_descriptions_are_allowed() {
        let mut b = Board::new_default();
        let cmd = Command::CreateTask {
            column: None,
            position: None,
            draft: draft(&"x".repeat(1000)),
        };
        execute(&mut b, Origin::Agent, cmd).unwrap();
    }

    #[test]
    fn user_can_move_anywhere() {
        let (mut b, id) = board_with_task();
        let to = col(&b, 4);
        execute(
            &mut b,
            Origin::User,
            Command::MoveTask {
                id,
                to_column: to,
                position: Some(99),
            },
        )
        .unwrap();
        assert_eq!(b.locate_task(id), Some((4, 0)));
        assert_eq!(task_count(&b), 1);
    }

    fn four_tasks() -> (Board, Vec<TaskId>) {
        let (mut b, first) = board_with_task();
        let mut ids = vec![first];
        for d in ["b", "c", "d"] {
            let Applied::Task(id) = execute(
                &mut b,
                Origin::User,
                Command::CreateTask {
                    column: None,
                    position: None,
                    draft: draft(d),
                },
            )
            .unwrap() else {
                panic!()
            };
            ids.push(id);
        }
        (b, ids)
    }

    fn names(b: &Board, c: usize) -> Vec<&str> {
        b.columns[c]
            .tasks
            .iter()
            .map(|t| t.description.as_str())
            .collect()
    }

    #[test]
    fn move_tasks_moves_a_run_in_order_to_another_column() {
        let (mut b, ids) = four_tasks();
        let c1 = col(&b, 1);
        execute(
            &mut b,
            Origin::User,
            Command::MoveTasks {
                ids: vec![ids[3], ids[1]],
                to_column: c1,
                position: 0,
            },
        )
        .unwrap();
        assert_eq!(names(&b, 0), ["first", "c"]);
        assert_eq!(names(&b, 1), ["d", "b"]);
    }

    #[test]
    fn move_tasks_reorders_within_a_column() {
        let (mut b, ids) = four_tasks();
        let c0 = col(&b, 0);
        // Without b and c the column is first, d; position 1 lands between them.
        execute(
            &mut b,
            Origin::User,
            Command::MoveTasks {
                ids: vec![ids[1], ids[2]],
                to_column: c0,
                position: 1,
            },
        )
        .unwrap();
        assert_eq!(names(&b, 0), ["first", "b", "c", "d"]);
        execute(
            &mut b,
            Origin::User,
            Command::MoveTasks {
                ids: vec![ids[0], ids[1]],
                to_column: c0,
                position: 2,
            },
        )
        .unwrap();
        assert_eq!(names(&b, 0), ["c", "d", "first", "b"]);
    }

    #[test]
    fn move_tasks_is_all_or_nothing() {
        let (mut b, ids) = four_tasks();
        let c1 = col(&b, 1);
        let before = names(&b, 0).join(",");
        for cmd in [
            Command::MoveTasks {
                ids: vec![ids[0], Uuid::new_v4()],
                to_column: c1,
                position: 0,
            },
            Command::MoveTasks {
                ids: vec![ids[0], ids[1]],
                to_column: c1,
                position: 1,
            },
            Command::MoveTasks {
                ids: vec![ids[0], ids[0]],
                to_column: c1,
                position: 0,
            },
            Command::MoveTasks {
                ids: vec![ids[0]],
                to_column: Uuid::new_v4(),
                position: 0,
            },
        ] {
            assert!(execute(&mut b, Origin::User, cmd).is_err());
        }
        assert_eq!(names(&b, 0).join(","), before);
        assert!(b.columns[1].tasks.is_empty());
    }

    #[test]
    fn agents_cannot_move_tasks_in_bulk() {
        let (mut b, ids) = four_tasks();
        let c1 = col(&b, 1);
        let r = execute(
            &mut b,
            Origin::Agent,
            Command::MoveTasks {
                ids: vec![ids[0]],
                to_column: c1,
                position: 0,
            },
        );
        assert!(matches!(r, Err(Error::AgentNotPermitted(_))));
        assert_eq!(names(&b, 0).len(), 4);
    }

    #[test]
    fn move_within_column_reorders() {
        let (mut b, first) = board_with_task();
        for d in ["b", "c"] {
            execute(
                &mut b,
                Origin::User,
                Command::CreateTask {
                    column: None,
                    position: None,
                    draft: draft(d),
                },
            )
            .unwrap();
        }
        let c0 = col(&b, 0);
        execute(
            &mut b,
            Origin::User,
            Command::MoveTask {
                id: first,
                to_column: c0,
                position: Some(2),
            },
        )
        .unwrap();
        let order: Vec<_> = b.columns[0]
            .tasks
            .iter()
            .map(|t| t.description.as_str())
            .collect();
        assert_eq!(order, ["b", "c", "first"]);
    }

    #[test]
    fn agent_can_only_move_one_step_right() {
        let (mut b, id) = board_with_task();
        let (c0, c1, c2) = (col(&b, 0), col(&b, 1), col(&b, 2));
        let mv = |to_column| Command::MoveTask {
            id,
            to_column,
            position: None,
        };
        assert!(matches!(
            execute(&mut b, Origin::Agent, mv(c2)),
            Err(Error::AgentNotPermitted(_))
        ));
        assert!(matches!(
            execute(&mut b, Origin::Agent, mv(c0)),
            Err(Error::AgentNotPermitted(_))
        ));
        execute(&mut b, Origin::Agent, mv(c1)).unwrap();
        assert!(matches!(
            execute(&mut b, Origin::Agent, mv(c0)),
            Err(Error::AgentNotPermitted(_))
        ));
        assert_eq!(b.locate_task(id), Some((1, 0)));
    }

    #[test]
    fn advance_moves_to_next_column_and_stops_at_last() {
        let (mut b, id) = board_with_task();
        for expected in 1..5 {
            execute(&mut b, Origin::Agent, Command::AdvanceTask { id }).unwrap();
            assert_eq!(b.locate_task(id).unwrap().0, expected);
        }
        assert!(matches!(
            execute(&mut b, Origin::Agent, Command::AdvanceTask { id }),
            Err(Error::Validation(_))
        ));
    }

    #[test]
    fn agent_creates_only_in_first_column() {
        let mut b = Board::new_default();
        let second = col(&b, 1);
        let first = col(&b, 0);
        let mk = |column| Command::CreateTask {
            column,
            position: None,
            draft: draft("t"),
        };
        assert!(matches!(
            execute(&mut b, Origin::Agent, mk(Some(second))),
            Err(Error::AgentNotPermitted(_))
        ));
        execute(&mut b, Origin::Agent, mk(Some(first))).unwrap();
        execute(&mut b, Origin::Agent, mk(None)).unwrap();
        assert_eq!(b.columns[0].tasks.len(), 2);
    }

    #[test]
    fn agent_cannot_touch_columns() {
        let mut b = Board::new_default();
        let id = col(&b, 0);
        let cmds = [
            Command::CreateColumn {
                position: None,
                title: "x".into(),
                description: String::new(),
            },
            Command::UpdateColumn {
                id,
                title: Some("x".into()),
                description: None,
            },
            Command::MoveColumn { id, position: 2 },
            Command::DeleteColumn { id, force: true },
            Command::RenameBoard { title: "x".into() },
            Command::UpdateProject {
                document_prompt: Some("x".into()),
                code_guidance: None,
            },
        ];
        let before = b.clone();
        for cmd in cmds {
            assert!(matches!(
                execute(&mut b, Origin::Agent, cmd),
                Err(Error::AgentNotPermitted(_))
            ));
        }
        assert_eq!(b, before);
    }

    #[test]
    fn delete_non_empty_column_requires_force() {
        let (mut b, _) = board_with_task();
        let id = col(&b, 0);
        assert!(matches!(
            execute(
                &mut b,
                Origin::User,
                Command::DeleteColumn { id, force: false }
            ),
            Err(Error::ColumnNotEmpty(_))
        ));
        execute(
            &mut b,
            Origin::User,
            Command::DeleteColumn { id, force: true },
        )
        .unwrap();
        assert_eq!(b.columns.len(), 4);
        assert_eq!(task_count(&b), 0);
    }

    #[test]
    fn move_column_reorders() {
        let mut b = Board::new_default();
        let id = col(&b, 0);
        execute(
            &mut b,
            Origin::User,
            Command::MoveColumn { id, position: 2 },
        )
        .unwrap();
        assert_eq!(b.column_index(id), Some(2));
        assert_eq!(b.columns.len(), 5);
    }

    #[test]
    fn update_merges_criteria_by_id() {
        let mut b = Board::new_default();
        execute(
            &mut b,
            Origin::User,
            Command::CreateTask {
                column: None,
                position: None,
                draft: TaskDraft {
                    description: "d".into(),
                    acceptance_criteria: vec![CriterionDraft {
                        text: "keep".into(),
                        ..Default::default()
                    }],
                    ..Default::default()
                },
            },
        )
        .unwrap();
        let task = b.columns[0].tasks[0].clone();
        let kept = task.acceptance_criteria[0].id;
        execute(
            &mut b,
            Origin::User,
            Command::UpdateTask {
                id: task.id,
                patch: TaskPatch {
                    acceptance_criteria: Some(vec![
                        CriterionDraft {
                            id: Some(kept),
                            text: "keep (edited)".into(),
                            done: true,
                        },
                        CriterionDraft {
                            text: "new".into(),
                            ..Default::default()
                        },
                    ]),
                    ..Default::default()
                },
            },
        )
        .unwrap();
        let t = b.task(task.id).unwrap();
        assert_eq!(t.acceptance_criteria[0].id, kept);
        assert_eq!(t.acceptance_criteria[0].text, "keep (edited)");
        assert_eq!(t.progress().done, 1);
        assert_eq!(t.progress().total, 2);
        assert_eq!(t.description, "d");
    }

    #[test]
    fn set_criterion_toggles() {
        let mut b = Board::new_default();
        execute(
            &mut b,
            Origin::User,
            Command::CreateTask {
                column: None,
                position: None,
                draft: TaskDraft {
                    description: "d".into(),
                    acceptance_criteria: vec![CriterionDraft {
                        text: "c".into(),
                        ..Default::default()
                    }],
                    ..Default::default()
                },
            },
        )
        .unwrap();
        let t = &b.columns[0].tasks[0];
        let (task, criterion) = (t.id, t.acceptance_criteria[0].id);
        execute(
            &mut b,
            Origin::Agent,
            Command::SetCriterion {
                task,
                criterion,
                done: true,
            },
        )
        .unwrap();
        assert!(b.task(task).unwrap().acceptance_criteria[0].done);
    }

    // ---- references ----

    use crate::model::Relation;

    fn add_task(b: &mut Board, description: &str) -> TaskId {
        let Applied::Task(id) = execute(
            b,
            Origin::User,
            Command::CreateTask {
                column: None,
                position: None,
                draft: draft(description),
            },
        )
        .unwrap() else {
            unreachable!()
        };
        id
    }

    fn set_refs(
        b: &mut Board,
        origin: Origin,
        id: TaskId,
        refs: &[(TaskId, Relation)],
    ) -> Result<Applied> {
        execute(
            b,
            origin,
            Command::UpdateTask {
                id,
                patch: TaskPatch {
                    references: Some(
                        refs.iter()
                            .map(|&(task, relation)| ReferenceDraft { task, relation })
                            .collect(),
                    ),
                    ..Default::default()
                },
            },
        )
    }

    fn refs_of(b: &Board, id: TaskId) -> Vec<(TaskId, Relation)> {
        b.task(id)
            .unwrap()
            .references
            .iter()
            .map(|r| (r.task, r.relation))
            .collect()
    }

    #[test]
    fn adding_a_reference_adds_the_mirror() {
        let mut b = Board::new_default();
        let (a, c) = (add_task(&mut b, "a"), add_task(&mut b, "c"));
        set_refs(&mut b, Origin::User, a, &[(c, Relation::Blocks)]).unwrap();
        assert_eq!(refs_of(&b, a), [(c, Relation::Blocks)]);
        assert_eq!(refs_of(&b, c), [(a, Relation::BlockedBy)]);
    }

    #[test]
    fn every_relation_mirrors_to_its_inverse() {
        for relation in Relation::ALL {
            let mut b = Board::new_default();
            let (a, c) = (add_task(&mut b, "a"), add_task(&mut b, "c"));
            set_refs(&mut b, Origin::User, a, &[(c, relation)]).unwrap();
            assert_eq!(refs_of(&b, c), [(a, relation.inverse())], "{relation:?}");
            assert_eq!(relation.inverse().inverse(), relation);
        }
    }

    #[test]
    fn removing_from_either_side_removes_both() {
        let mut b = Board::new_default();
        let (a, c) = (add_task(&mut b, "a"), add_task(&mut b, "c"));
        set_refs(&mut b, Origin::User, a, &[(c, Relation::RelatesTo)]).unwrap();
        set_refs(&mut b, Origin::User, a, &[]).unwrap();
        assert!(refs_of(&b, a).is_empty() && refs_of(&b, c).is_empty());

        set_refs(&mut b, Origin::User, a, &[(c, Relation::RelatesTo)]).unwrap();
        set_refs(&mut b, Origin::User, c, &[]).unwrap();
        assert!(refs_of(&b, a).is_empty() && refs_of(&b, c).is_empty());
    }

    #[test]
    fn changing_a_relation_replaces_the_mirror() {
        let mut b = Board::new_default();
        let (a, c) = (add_task(&mut b, "a"), add_task(&mut b, "c"));
        set_refs(&mut b, Origin::User, a, &[(c, Relation::Blocks)]).unwrap();
        set_refs(&mut b, Origin::User, a, &[(c, Relation::Duplicates)]).unwrap();
        assert_eq!(refs_of(&b, a), [(c, Relation::Duplicates)]);
        assert_eq!(refs_of(&b, c), [(a, Relation::DuplicatedBy)]);
    }

    #[test]
    fn unrelated_references_are_untouched_by_an_update() {
        let mut b = Board::new_default();
        let (a, c, d) = (
            add_task(&mut b, "a"),
            add_task(&mut b, "c"),
            add_task(&mut b, "d"),
        );
        set_refs(
            &mut b,
            Origin::User,
            a,
            &[(c, Relation::Blocks), (d, Relation::RelatesTo)],
        )
        .unwrap();
        set_refs(&mut b, Origin::User, a, &[(d, Relation::RelatesTo)]).unwrap();
        assert!(refs_of(&b, c).is_empty());
        assert_eq!(refs_of(&b, d), [(a, Relation::RelatesTo)]);
    }

    #[test]
    fn a_patch_without_references_leaves_them_alone() {
        let mut b = Board::new_default();
        let (a, c) = (add_task(&mut b, "a"), add_task(&mut b, "c"));
        set_refs(&mut b, Origin::User, a, &[(c, Relation::Blocks)]).unwrap();
        execute(
            &mut b,
            Origin::User,
            Command::UpdateTask {
                id: a,
                patch: TaskPatch {
                    description: Some("renamed".into()),
                    ..Default::default()
                },
            },
        )
        .unwrap();
        assert_eq!(refs_of(&b, a), [(c, Relation::Blocks)]);
        assert_eq!(refs_of(&b, c), [(a, Relation::BlockedBy)]);
    }

    #[test]
    fn invalid_references_are_rejected_without_side_effects() {
        let mut b = Board::new_default();
        let (a, c) = (add_task(&mut b, "a"), add_task(&mut b, "c"));
        let before = b.clone();
        let ghost = Uuid::new_v4();
        assert!(matches!(
            set_refs(&mut b, Origin::User, a, &[(a, Relation::Blocks)]),
            Err(Error::Validation(_))
        ));
        assert!(matches!(
            set_refs(
                &mut b,
                Origin::User,
                a,
                &[(c, Relation::Blocks), (ghost, Relation::Blocks)]
            ),
            Err(Error::NotFound { .. })
        ));
        assert_eq!(b, before);
    }

    #[test]
    fn deleting_a_task_removes_references_to_it() {
        let mut b = Board::new_default();
        let (a, c, d) = (
            add_task(&mut b, "a"),
            add_task(&mut b, "c"),
            add_task(&mut b, "d"),
        );
        set_refs(
            &mut b,
            Origin::User,
            a,
            &[(c, Relation::Blocks), (d, Relation::RelatesTo)],
        )
        .unwrap();
        execute(&mut b, Origin::User, Command::DeleteTask { id: c }).unwrap();
        assert_eq!(refs_of(&b, a), [(d, Relation::RelatesTo)]);
    }

    #[test]
    fn deleting_a_column_removes_references_to_its_tasks() {
        let mut b = Board::new_default();
        let (a, c) = (add_task(&mut b, "a"), add_task(&mut b, "c"));
        let to = col(&b, 1);
        execute(
            &mut b,
            Origin::User,
            Command::MoveTask {
                id: c,
                to_column: to,
                position: None,
            },
        )
        .unwrap();
        set_refs(&mut b, Origin::User, a, &[(c, Relation::Blocks)]).unwrap();
        execute(
            &mut b,
            Origin::User,
            Command::DeleteColumn {
                id: to,
                force: true,
            },
        )
        .unwrap();
        assert!(refs_of(&b, a).is_empty());
    }

    #[test]
    fn agents_can_edit_references() {
        let mut b = Board::new_default();
        let (a, c) = (add_task(&mut b, "a"), add_task(&mut b, "c"));
        set_refs(&mut b, Origin::Agent, a, &[(c, Relation::Blocks)]).unwrap();
        assert_eq!(refs_of(&b, c), [(a, Relation::BlockedBy)]);
    }

    #[test]
    fn references_round_trip_through_json() {
        let mut b = Board::new_default();
        let (a, c) = (add_task(&mut b, "a"), add_task(&mut b, "c"));
        set_refs(&mut b, Origin::User, a, &[(c, Relation::DuplicatedBy)]).unwrap();
        let json = serde_json::to_string(&b).unwrap();
        assert!(json.contains("\"duplicated_by\""));
        let back: Board = serde_json::from_str(&json).unwrap();
        assert_eq!(back, b);
        // Boards written before references existed still load.
        assert!(
            !serde_json::to_string(&Board::new_default())
                .unwrap()
                .contains("references")
        );
    }

    #[test]
    fn project_settings_update_and_trim() {
        let mut b = Board::new_default();
        execute(
            &mut b,
            Origin::User,
            Command::UpdateProject {
                document_prompt: Some("  Write in plain English.  ".into()),
                code_guidance: None,
            },
        )
        .unwrap();
        execute(
            &mut b,
            Origin::User,
            Command::UpdateProject {
                document_prompt: None,
                code_guidance: Some("Prefer small functions.\n".into()),
            },
        )
        .unwrap();
        assert_eq!(b.project.document_prompt, "Write in plain English.");
        assert_eq!(b.project.code_guidance, "Prefer small functions.");
    }

    #[test]
    fn project_settings_round_trip_and_stay_out_of_empty_boards() {
        let mut b = Board::new_default();
        assert!(!serde_json::to_string(&b).unwrap().contains("project"));
        b.project.code_guidance = "Use Rust 2024.".into();
        b.project
            .extra
            .insert("future".into(), serde_json::json!(1));
        let back: Board = serde_json::from_str(&serde_json::to_string(&b).unwrap()).unwrap();
        assert_eq!(back, b);
    }

    // ---- task numbers ----

    fn number_of(b: &Board, id: TaskId) -> u64 {
        b.task(id).unwrap().number
    }

    #[test]
    fn new_tasks_get_increasing_numbers_starting_at_one() {
        let mut b = Board::new_default();
        let ids: Vec<_> = ["a", "b", "c"]
            .iter()
            .map(|d| add_task(&mut b, d))
            .collect();
        let numbers: Vec<_> = ids.iter().map(|&id| number_of(&b, id)).collect();
        assert_eq!(numbers, [1, 2, 3]);
    }

    #[test]
    fn numbers_never_change_and_survive_deleting_other_tasks() {
        let mut b = Board::new_default();
        let (a, c, d) = (
            add_task(&mut b, "a"),
            add_task(&mut b, "c"),
            add_task(&mut b, "d"),
        );
        execute(&mut b, Origin::User, Command::DeleteTask { id: c }).unwrap();
        assert_eq!((number_of(&b, a), number_of(&b, d)), (1, 3));

        // Moving and editing leave the number alone.
        execute(&mut b, Origin::Agent, Command::AdvanceTask { id: a }).unwrap();
        set_refs(&mut b, Origin::User, a, &[(d, Relation::Blocks)]).unwrap();
        assert_eq!(number_of(&b, a), 1);
    }

    #[test]
    fn a_deleted_tasks_number_is_never_reused_even_the_highest() {
        let mut b = Board::new_default();
        let a = add_task(&mut b, "a");
        let last = add_task(&mut b, "last");
        assert_eq!(number_of(&b, last), 2);
        execute(&mut b, Origin::User, Command::DeleteTask { id: last }).unwrap();
        let next = add_task(&mut b, "next");
        assert_eq!(number_of(&b, next), 3, "2 stays retired");
        assert_eq!(number_of(&b, a), 1);
    }

    #[test]
    fn deleting_a_column_retires_its_numbers_too() {
        let mut b = Board::new_default();
        let id = add_task(&mut b, "a");
        let column = b.locate_task(id).unwrap().0;
        let column_id = b.columns[column].id;
        execute(
            &mut b,
            Origin::User,
            Command::DeleteColumn {
                id: column_id,
                force: true,
            },
        )
        .unwrap();
        let mut again = b.clone();
        again.columns.push(Column::new("Back", ""));
        let new_id = add_task(&mut again, "b");
        assert_eq!(number_of(&again, new_id), 2);
    }

    // ---- agent change markers ----

    fn change_of(b: &Board, id: TaskId) -> Option<ChangeKind> {
        b.task(id).unwrap().agent_change.as_ref().map(|c| c.kind)
    }

    fn criteria_task(b: &mut Board, origin: Origin) -> (TaskId, Uuid) {
        let Applied::Task(id) = execute(
            b,
            origin,
            Command::CreateTask {
                column: None,
                position: None,
                draft: TaskDraft {
                    description: "with criteria".into(),
                    acceptance_criteria: vec![CriterionDraft {
                        text: "c".into(),
                        ..Default::default()
                    }],
                    ..Default::default()
                },
            },
        )
        .unwrap() else {
            unreachable!()
        };
        (id, b.task(id).unwrap().acceptance_criteria[0].id)
    }

    #[test]
    fn a_task_created_by_an_agent_is_marked_created() {
        let mut b = Board::new_default();
        let (id, _) = criteria_task(&mut b, Origin::Agent);
        assert_eq!(change_of(&b, id), Some(ChangeKind::Created));
        let change = b.task(id).unwrap().agent_change.as_ref().unwrap();
        assert_eq!(change.at, b.task(id).unwrap().updated_at);
    }

    #[test]
    fn a_task_created_by_the_user_is_not_marked() {
        let mut b = Board::new_default();
        let id = add_task(&mut b, "mine");
        assert_eq!(change_of(&b, id), None);
    }

    #[test]
    fn each_kind_of_agent_change_is_recorded() {
        let mut b = Board::new_default();
        let (id, criterion) = criteria_task(&mut b, Origin::User);

        execute(
            &mut b,
            Origin::Agent,
            Command::SetCriterion {
                task: id,
                criterion,
                done: true,
            },
        )
        .unwrap();
        assert_eq!(change_of(&b, id), Some(ChangeKind::Progress));

        execute(&mut b, Origin::Agent, Command::AdvanceTask { id }).unwrap();
        assert_eq!(change_of(&b, id), Some(ChangeKind::Moved));

        execute(
            &mut b,
            Origin::Agent,
            Command::UpdateTask {
                id,
                patch: TaskPatch {
                    extended_description: Some("more".into()),
                    ..Default::default()
                },
            },
        )
        .unwrap();
        assert_eq!(change_of(&b, id), Some(ChangeKind::Edited));
    }

    #[test]
    fn the_other_end_of_a_link_counts_as_edited() {
        let mut b = Board::new_default();
        let (a, c) = (add_task(&mut b, "a"), add_task(&mut b, "c"));
        set_refs(&mut b, Origin::Agent, a, &[(c, Relation::Blocks)]).unwrap();
        assert_eq!(change_of(&b, a), Some(ChangeKind::Edited));
        assert_eq!(
            change_of(&b, c),
            Some(ChangeKind::Edited),
            "its link changed too"
        );
    }

    #[test]
    fn an_agent_deleting_a_task_marks_the_tasks_that_linked_to_it() {
        let mut b = Board::new_default();
        let (a, c, d) = (
            add_task(&mut b, "a"),
            add_task(&mut b, "c"),
            add_task(&mut b, "d"),
        );
        set_refs(&mut b, Origin::User, a, &[(c, Relation::Blocks)]).unwrap();
        execute(&mut b, Origin::Agent, Command::DeleteTask { id: c }).unwrap();
        assert_eq!(change_of(&b, a), Some(ChangeKind::Edited));
        assert_eq!(change_of(&b, d), None, "unrelated tasks are not marked");
    }

    #[test]
    fn a_change_by_the_user_clears_the_marker() {
        let mut b = Board::new_default();
        let (id, _) = criteria_task(&mut b, Origin::Agent);
        assert!(change_of(&b, id).is_some());
        let to = col(&b, 2);
        execute(
            &mut b,
            Origin::User,
            Command::MoveTask {
                id,
                to_column: to,
                position: None,
            },
        )
        .unwrap();
        assert_eq!(
            change_of(&b, id),
            None,
            "moving it yourself means you have seen it"
        );

        execute(&mut b, Origin::Agent, Command::AdvanceTask { id }).unwrap();
        assert!(change_of(&b, id).is_some());
        execute(
            &mut b,
            Origin::User,
            Command::UpdateTask {
                id,
                patch: TaskPatch {
                    description: Some("edited by me".into()),
                    ..Default::default()
                },
            },
        )
        .unwrap();
        assert_eq!(change_of(&b, id), None);
    }

    #[test]
    fn untouched_tasks_keep_their_marker() {
        let mut b = Board::new_default();
        let (marked, _) = criteria_task(&mut b, Origin::Agent);
        let other = add_task(&mut b, "other");
        let to = col(&b, 3);
        execute(
            &mut b,
            Origin::User,
            Command::MoveTask {
                id: other,
                to_column: to,
                position: None,
            },
        )
        .unwrap();
        assert_eq!(change_of(&b, marked), Some(ChangeKind::Created));
    }

    #[test]
    fn a_change_that_changes_nothing_does_not_mark() {
        let mut b = Board::new_default();
        let (id, criterion) = criteria_task(&mut b, Origin::User);
        // The criterion is already not done: unticking it is a no-op.
        execute(
            &mut b,
            Origin::Agent,
            Command::SetCriterion {
                task: id,
                criterion,
                done: false,
            },
        )
        .unwrap();
        assert_eq!(change_of(&b, id), None);
    }

    #[test]
    fn a_failed_agent_command_marks_nothing() {
        let mut b = Board::new_default();
        let id = add_task(&mut b, "a");
        let ghost = Uuid::new_v4();
        assert!(set_refs(&mut b, Origin::Agent, id, &[(ghost, Relation::Blocks)]).is_err());
        assert_eq!(change_of(&b, id), None);
    }

    #[test]
    fn markers_round_trip_and_old_boards_load_without_them() {
        let mut b = Board::new_default();
        let (id, _) = criteria_task(&mut b, Origin::Agent);
        let json = serde_json::to_string(&b).unwrap();
        assert!(json.contains("\"agent_change\"") && json.contains("\"created\""));
        let back: Board = serde_json::from_str(&json).unwrap();
        assert_eq!(back, b);
        assert_eq!(change_of(&back, id), Some(ChangeKind::Created));

        let plain = serde_json::to_string(&Board::new_default()).unwrap();
        assert!(
            !plain.contains("agent_change"),
            "absent when there is nothing to mark"
        );
    }
}
