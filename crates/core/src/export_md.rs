//! One-way Markdown export of a board.

use std::fmt::Write;

use crate::model::Board;

pub fn to_markdown(board: &Board) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "# {}", board.title);

    for column in &board.columns {
        let _ = write!(out, "\n## {}\n", column.title);
        if !column.description.is_empty() {
            for line in column.description.lines() {
                let _ = writeln!(out, "> {line}");
            }
        }
        if column.tasks.is_empty() {
            out.push_str("\n_No tasks._\n");
        }

        for task in &column.tasks {
            let _ = write!(
                out,
                "\n### #{} {}\n",
                task.number,
                single_line(&task.description)
            );
            if !task.extended_description.is_empty() {
                let _ = write!(out, "\n{}\n", task.extended_description);
            }
            if !task.requirements.is_empty() {
                out.push_str("\n**Requirements**\n\n");
                for r in &task.requirements {
                    let _ = writeln!(out, "- {r}");
                }
            }
            if !task.acceptance_criteria.is_empty() {
                let p = task.progress();
                let _ = write!(
                    out,
                    "\n**Acceptance criteria** ({}/{})\n\n",
                    p.done, p.total
                );
                for c in &task.acceptance_criteria {
                    let mark = if c.done { 'x' } else { ' ' };
                    let _ = writeln!(out, "- [{mark}] {}", c.text);
                }
            }
            let references: Vec<_> = task
                .references
                .iter()
                .filter_map(|r| board.task(r.task).map(|other| (r.relation, other)))
                .collect();
            if !references.is_empty() {
                out.push_str("\n**References**\n\n");
                for (relation, other) in references {
                    let _ = writeln!(
                        out,
                        "- {} #{} \"{}\"",
                        relation.label(),
                        other.number,
                        single_line(&other.description)
                    );
                }
            }
        }
    }
    out
}

/// Headings must be a single line.
fn single_line(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::command::{Applied, Command, CriterionDraft, Origin, TaskDraft};
    use crate::ops::execute;

    #[test]
    fn export_snapshot() {
        let mut board = Board::new_default();
        board.title = "Demo".into();
        board.columns.truncate(2);
        execute(
            &mut board,
            Origin::User,
            Command::CreateTask {
                column: None,
                position: None,
                draft: TaskDraft {
                    description: "Write the parser\nfor boards".into(),
                    extended_description: "Handle unknown fields.".into(),
                    requirements: vec!["serde".into()],
                    acceptance_criteria: vec![
                        CriterionDraft {
                            text: "round trips".into(),
                            done: true,
                            ..Default::default()
                        },
                        CriterionDraft {
                            text: "has tests".into(),
                            ..Default::default()
                        },
                    ],
                },
            },
        )
        .unwrap();
        insta::assert_snapshot!(to_markdown(&board));
    }

    #[test]
    fn export_lists_references() {
        use crate::command::{ReferenceDraft, TaskPatch};
        use crate::model::Relation;

        let mut board = Board::new_default();
        let mut ids = Vec::new();
        for d in ["Build the API", "Write the docs"] {
            let Applied::Task(id) = execute(
                &mut board,
                Origin::User,
                Command::CreateTask {
                    column: None,
                    position: None,
                    draft: TaskDraft {
                        description: d.into(),
                        ..Default::default()
                    },
                },
            )
            .unwrap() else {
                unreachable!()
            };
            ids.push(id);
        }
        execute(
            &mut board,
            Origin::User,
            Command::UpdateTask {
                id: ids[0],
                patch: TaskPatch {
                    references: Some(vec![ReferenceDraft {
                        task: ids[1],
                        relation: Relation::Blocks,
                    }]),
                    ..Default::default()
                },
            },
        )
        .unwrap();
        let md = to_markdown(&board);
        assert!(
            md.contains("**References**\n\n- blocks #2 \"Write the docs\""),
            "{md}"
        );
        assert!(md.contains("- is blocked by #1 \"Build the API\""), "{md}");
    }
}
