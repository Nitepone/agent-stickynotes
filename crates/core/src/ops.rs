//! Pure command execution against a [`Board`]. No locking, no I/O.

use chrono::Utc;
use serde_json::Map;
use uuid::Uuid;

use crate::command::{Applied, Command, CriterionDraft, Origin, TaskDraft, TaskPatch};
use crate::error::{Error, Result};
use crate::model::{Board, Column, ColumnId, Criterion, Task, TaskId};

/// Validate and apply `cmd` to `board`. On error the board is unchanged.
pub fn execute(board: &mut Board, origin: Origin, cmd: Command) -> Result<Applied> {
    if origin == Origin::Agent {
        check_agent_rules(board, &cmd)?;
    }

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
            board.columns.remove(idx);
            Ok(Applied::Column(id))
        }
        Command::RenameBoard { title } => {
            board.title = required(&title, "board title")?;
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
        Command::UpdateTask { .. }
        | Command::AdvanceTask { .. }
        | Command::DeleteTask { .. }
        | Command::SetCriterion { .. } => Ok(()),
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
    let now = Utc::now();
    let task = Task {
        id: Uuid::new_v4(),
        description: required(&draft.description, "task description")?,
        extended_description: draft.extended_description.trim().to_string(),
        requirements: clean_lines(draft.requirements),
        acceptance_criteria: merge_criteria(&[], draft.acceptance_criteria),
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
    let description = patch
        .description
        .map(|d| required(&d, "task description"))
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
    task.updated_at = Utc::now();
    Ok(Applied::Task(id))
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
    Error::NotFound {
        kind,
        id: id.to_string(),
    }
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
}
