//! Size limits on what a task and a board may hold.
//!
//! Every save rewrites the whole board and every board response carries all of
//! it, so one runaway writer (a looping agent, a pasted megabyte) would make
//! everything slow. The limits are generous: ordinary use never meets them.
//! They apply to the user and to agents alike, and are checked in
//! [`ops::execute`](crate::ops::execute) before a command changes anything.
//!
//! A board that is already over a limit still loads, and can be edited
//! downward: a value is only refused if it is over the limit *and* bigger than
//! what the task holds now.

use crate::command::{Command, CriterionDraft, TaskDraft, TaskPatch};
use crate::error::{Error, Result};
use crate::model::{Board, Task};

pub const MAX_DESCRIPTION_CHARS: usize = 2_000;
pub const MAX_EXTENDED_DESCRIPTION_CHARS: usize = 50_000;
/// One requirement or one acceptance criterion.
pub const MAX_ITEM_CHARS: usize = 1_000;
pub const MAX_REQUIREMENTS: usize = 100;
pub const MAX_CRITERIA: usize = 100;
pub const MAX_REFERENCES: usize = 50;
pub const MAX_TASKS: usize = 2_000;

/// The workflow rule that tells agents about the limits.
pub fn rule() -> String {
    format!(
        "- Size limits: a description is at most {MAX_DESCRIPTION_CHARS} characters, an extended \
         description {MAX_EXTENDED_DESCRIPTION_CHARS}, each requirement or criterion \
         {MAX_ITEM_CHARS}; a task holds at most {MAX_REQUIREMENTS} requirements, {MAX_CRITERIA} \
         criteria and {MAX_REFERENCES} references, and a board at most {MAX_TASKS} tasks. A write \
         over a limit is refused with an error naming it."
    )
}

/// Refuse `cmd` if it would write more than the limits allow.
pub fn check(board: &Board, cmd: &Command) -> Result<()> {
    match cmd {
        Command::CreateTask { draft, .. } => {
            let count = board.tasks().count();
            if count >= MAX_TASKS {
                return Err(over(format!(
                    "the board already has {count} tasks; the limit is {MAX_TASKS}"
                )));
            }
            check_draft(draft)
        }
        Command::UpdateTask { id, patch } => check_patch(board.task(*id), patch),
        _ => Ok(()),
    }
}

fn over(message: String) -> Error {
    Error::Validation(message)
}

fn chars(text: &str) -> usize {
    text.chars().count()
}

/// A text value: within the limit, or no bigger than what is stored now.
fn check_text(field: &str, text: &str, max: usize, now: usize) -> Result<()> {
    let n = chars(text);
    if n > max && n > now {
        return Err(over(format!(
            "{field} is {n} characters; the limit is {max}"
        )));
    }
    Ok(())
}

/// A list length: within the limit, or no longer than the list stored now.
fn check_count(field: &str, n: usize, max: usize, now: usize) -> Result<()> {
    if n > max && n > now {
        return Err(over(format!("{field}: {n} entries; the limit is {max}")));
    }
    Ok(())
}

fn check_requirements(list: &[String], existing: &[String]) -> Result<()> {
    check_count("requirements", list.len(), MAX_REQUIREMENTS, existing.len())?;
    for (i, text) in list.iter().enumerate() {
        // An unchanged long item stays; only a new long item is refused.
        if !existing.contains(text) {
            check_text(&format!("requirement {}", i + 1), text, MAX_ITEM_CHARS, 0)?;
        }
    }
    Ok(())
}

fn check_criteria(list: &[CriterionDraft], task: Option<&Task>) -> Result<()> {
    let existing = task.map_or(&[][..], |t| &t.acceptance_criteria[..]);
    check_count(
        "acceptance criteria",
        list.len(),
        MAX_CRITERIA,
        existing.len(),
    )?;
    for (i, item) in list.iter().enumerate() {
        let unchanged = existing
            .iter()
            .any(|c| Some(c.id) == item.id && c.text == item.text);
        if !unchanged {
            check_text(
                &format!("acceptance criterion {}", i + 1),
                &item.text,
                MAX_ITEM_CHARS,
                0,
            )?;
        }
    }
    Ok(())
}

fn check_draft(draft: &TaskDraft) -> Result<()> {
    check_text("description", &draft.description, MAX_DESCRIPTION_CHARS, 0)?;
    check_text(
        "extended description",
        &draft.extended_description,
        MAX_EXTENDED_DESCRIPTION_CHARS,
        0,
    )?;
    check_requirements(&draft.requirements, &[])?;
    check_criteria(&draft.acceptance_criteria, None)
}

fn check_patch(task: Option<&Task>, patch: &TaskPatch) -> Result<()> {
    // A missing task is reported by the command itself.
    let now = |f: fn(&Task) -> usize| task.map_or(0, f);
    if let Some(text) = &patch.description {
        check_text(
            "description",
            text,
            MAX_DESCRIPTION_CHARS,
            now(|t| chars(&t.description)),
        )?;
    }
    if let Some(text) = &patch.extended_description {
        check_text(
            "extended description",
            text,
            MAX_EXTENDED_DESCRIPTION_CHARS,
            now(|t| chars(&t.extended_description)),
        )?;
    }
    if let Some(list) = &patch.requirements {
        check_requirements(list, task.map_or(&[][..], |t| &t.requirements[..]))?;
    }
    if let Some(list) = &patch.acceptance_criteria {
        check_criteria(list, task)?;
    }
    if let Some(list) = &patch.references {
        check_count(
            "references",
            list.len(),
            MAX_REFERENCES,
            now(|t| t.references.len()),
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::command::{Applied, Origin};
    use crate::model::TaskId;
    use crate::ops::execute;

    fn create(b: &mut Board, origin: Origin, draft: TaskDraft) -> Result<TaskId> {
        match execute(
            b,
            origin,
            Command::CreateTask {
                column: None,
                position: None,
                draft,
            },
        )? {
            Applied::Task(id) => Ok(id),
            _ => unreachable!(),
        }
    }

    fn update(b: &mut Board, id: TaskId, patch: TaskPatch) -> Result<()> {
        execute(b, Origin::User, Command::UpdateTask { id, patch }).map(|_| ())
    }

    fn plain() -> TaskDraft {
        TaskDraft {
            description: "t".into(),
            ..Default::default()
        }
    }

    fn text(n: usize) -> String {
        "x".repeat(n)
    }

    fn rejected(r: Result<impl std::fmt::Debug>, needles: &[&str]) {
        let msg = r.expect_err("should be refused").to_string();
        for n in needles {
            assert!(msg.contains(n), "{msg:?} should mention {n:?}");
        }
    }

    #[test]
    fn text_fields_stop_at_their_limit_for_everyone() {
        for origin in [Origin::User, Origin::Agent] {
            let mut b = Board::new_default();
            let draft = |d: &str, e: &str| TaskDraft {
                description: d.into(),
                extended_description: e.into(),
                ..Default::default()
            };
            create(
                &mut b,
                origin,
                draft(
                    &text(MAX_DESCRIPTION_CHARS),
                    &text(MAX_EXTENDED_DESCRIPTION_CHARS),
                ),
            )
            .expect("at the limit is fine");
            rejected(
                create(&mut b, origin, draft(&text(MAX_DESCRIPTION_CHARS + 1), "")),
                &["description", "2001", "2000"],
            );
            rejected(
                create(
                    &mut b,
                    origin,
                    draft("ok", &text(MAX_EXTENDED_DESCRIPTION_CHARS + 1)),
                ),
                &["extended description", "50000"],
            );
        }
    }

    #[test]
    fn requirements_and_criteria_are_limited_in_size_and_number() {
        let mut b = Board::new_default();
        let id = create(&mut b, Origin::User, plain()).unwrap();
        let reqs = |n: usize, len: usize| TaskPatch {
            requirements: Some(vec![text(len); n]),
            ..Default::default()
        };
        update(&mut b, id, reqs(MAX_REQUIREMENTS, MAX_ITEM_CHARS)).expect("at the limits");
        rejected(
            update(&mut b, id, reqs(MAX_REQUIREMENTS + 1, 1)),
            &["requirements", "101", "100"],
        );
        rejected(
            update(&mut b, id, reqs(1, MAX_ITEM_CHARS + 1)),
            &["requirement 1", "1001", "1000"],
        );

        let crit = |n: usize, len: usize| TaskPatch {
            acceptance_criteria: Some(
                (0..n)
                    .map(|_| CriterionDraft {
                        id: None,
                        text: text(len),
                        done: false,
                    })
                    .collect(),
            ),
            ..Default::default()
        };
        update(&mut b, id, crit(MAX_CRITERIA, MAX_ITEM_CHARS)).expect("at the limits");
        rejected(
            update(&mut b, id, crit(MAX_CRITERIA + 1, 1)),
            &["acceptance criteria", "101", "100"],
        );
        rejected(
            update(&mut b, id, crit(1, MAX_ITEM_CHARS + 1)),
            &["acceptance criterion 1", "1000"],
        );
    }

    #[test]
    fn references_and_tasks_per_board_are_limited() {
        let mut b = Board::new_default();
        let id = create(&mut b, Origin::User, plain()).unwrap();
        let refs = |n: usize| TaskPatch {
            references: Some(
                (0..n)
                    .map(|_| crate::command::ReferenceDraft {
                        task: id,
                        relation: crate::model::Relation::RelatesTo,
                    })
                    .collect(),
            ),
            ..Default::default()
        };
        rejected(
            update(&mut b, id, refs(MAX_REFERENCES + 1)),
            &["references", "50"],
        );

        for _ in 1..MAX_TASKS {
            create(&mut b, Origin::User, plain()).expect("under the limit");
        }
        assert_eq!(b.tasks().count(), MAX_TASKS);
        rejected(
            create(&mut b, Origin::Agent, plain()),
            &["2000 tasks", "limit is 2000"],
        );
        rejected(create(&mut b, Origin::User, plain()), &["limit is 2000"]);
    }

    #[test]
    fn a_task_already_over_a_limit_can_be_edited_downward() {
        let mut b = Board::new_default();
        let id = create(&mut b, Origin::User, plain()).unwrap();
        // An old board: the task is bigger than today's limits.
        {
            let t = &mut b.columns[0].tasks[0];
            t.description = text(MAX_DESCRIPTION_CHARS + 500);
            t.requirements = vec![text(MAX_ITEM_CHARS + 200); MAX_REQUIREMENTS + 20];
        }
        let desc = |n: usize| TaskPatch {
            description: Some(text(n)),
            ..Default::default()
        };
        update(&mut b, id, desc(MAX_DESCRIPTION_CHARS + 100)).expect("smaller than before");
        update(&mut b, id, desc(MAX_DESCRIPTION_CHARS)).expect("down to the limit");
        rejected(
            update(&mut b, id, desc(MAX_DESCRIPTION_CHARS + 1)),
            &["description"],
        );

        let mut reqs = b.columns[0].tasks[0].requirements.clone();
        reqs.truncate(MAX_REQUIREMENTS + 10);
        update(
            &mut b,
            id,
            TaskPatch {
                requirements: Some(reqs.clone()),
                ..Default::default()
            },
        )
        .expect("fewer, and the long ones are unchanged");
        reqs.push(text(MAX_ITEM_CHARS + 1));
        rejected(
            update(
                &mut b,
                id,
                TaskPatch {
                    requirements: Some(reqs),
                    ..Default::default()
                },
            ),
            &["requirements"],
        );
        // Editing something else leaves the oversize fields alone.
        update(
            &mut b,
            id,
            TaskPatch {
                category: Some("Docs".into()),
                ..Default::default()
            },
        )
        .expect("unrelated edits are not blocked");
    }

    #[test]
    fn the_agent_guide_tells_agents_the_limits() {
        let text = crate::agent_guide::mcp_instructions("B", None);
        assert!(text.contains("Size limits"));
        assert!(text.contains(&MAX_TASKS.to_string()));
        assert!(text.contains(&MAX_DESCRIPTION_CHARS.to_string()));
        let board = Board::new_default();
        assert!(crate::agent_guide::skill_markdown(&board).contains("Size limits"));
    }
}
