//! What agents are told about the board. The MCP server instructions and the
//! exported Claude Code skill are both built from this, so they never drift.

use std::fmt::Write;

use crate::model::Board;

/// The tools the MCP server offers, with a one-line purpose each.
pub const TOOLS: &[(&str, &str)] = &[
    (
        "project_get",
        "the project's instructions: how to write documents and code",
    ),
    (
        "board_get",
        "columns in order with their entry criteria, task summaries, revision",
    ),
    ("task_list", "task summaries, optionally for one column"),
    (
        "task_get",
        "one task in full, plus the next column and its entry criteria",
    ),
    ("task_create", "create a task (always in the first column)"),
    (
        "task_update",
        "edit a task's text, requirements, criteria, references or category",
    ),
    (
        "task_advance",
        "move a task one column to the right once it meets that column's bar",
    ),
    ("task_delete", "delete a task"),
    ("criterion_set", "tick or untick an acceptance criterion"),
    (
        "artifact_add",
        "attach a Markdown, image or PDF file to a task (stored in the project's artifacts folder)",
    ),
    (
        "artifact_get",
        "read an attached artifact (text for Markdown and SVG)",
    ),
    (
        "artifact_detach",
        "detach an artifact from a task; the file stays on disk",
    ),
];

/// The rules of the workflow, as a Markdown bullet list.
pub const WORKFLOW_RULES: &str = "\
- Start by calling project_get and follow the project's document_prompt and code_guidance in \
everything you write.
- Columns are an ordered pipeline, left to right. Each column's description is the bar a task \
must meet to enter that column.
- You move tasks only with task_advance, one column at a time, left to right. Before advancing, \
read the task with task_get and check that it meets next_column.description. Only the human moves \
tasks backwards or skips columns.
- Every task has a short permanent number shown as #12. The user may refer to tasks that way, \
and every tool accepts a number such as #12 wherever it takes a task id.
- New tasks always start in the first column.
- Keep a task's description short (about 200 characters, sticky-note sized); put detail in \
extended_description, requirements and acceptance_criteria.
- Group related tasks with the optional category on task_create and task_update (an empty string \
clears it); tasks of one category in a column stack on the board. Reuse an existing category where \
one fits; names match case-insensitively.
- Tick acceptance criteria with criterion_set as you complete them.
- Link related tasks with references in task_update (blocks, blocked_by, relates_to, duplicates, \
duplicated_by); the other task is updated to match.
- Attach documents and diagrams you produce for a task with artifact_add (Markdown, images or PDFs) \
instead of pasting them into the description. Artifacts cannot be replaced: add a new one and \
detach the old; detaching never deletes the file.
- The human may disable write access at any time; write tools then fail and you should tell the user.
- Write tools accept expected_revision. If it no longer matches, the board changed: re-read and retry.
- Columns cannot be created, edited, reordered or deleted by agents, and neither can project settings.";

/// The text of the MCP `instructions` field.
pub fn mcp_instructions() -> String {
    format!(
        "This server exposes the user's kanban board (agent-stickynotes).\n\nWorkflow rules:\n{WORKFLOW_RULES}\n{}",
        crate::limits::rule()
    )
}

/// A Claude Code skill (`SKILL.md`) describing how to work with this board,
/// including the project's own instructions as they are right now.
pub fn skill_markdown(board: &Board) -> String {
    let mut out = String::new();
    out.push_str(
        "---\n\
         name: stickynotes-board\n\
         description: Work with this project's sticky-notes kanban board through the \
         \"stickynotes\" MCP server: find tasks, record progress and move tasks through the \
         workflow. Use when planning, starting or finishing work on this project.\n\
         ---\n\n",
    );
    let _ = write!(
        out,
        "# Working with the kanban board\n\n\
         The board \"{}\" is served by the `stickynotes` MCP server. If its tools are not \
         available, ask the user to connect it (Agent > Connect Agent in the app).\n\n",
        board.title.replace('"', "'")
    );

    out.push_str("## Workflow\n\n");
    out.push_str(WORKFLOW_RULES);
    out.push('\n');
    out.push_str(&crate::limits::rule());
    out.push_str("\n\n## Tools\n\n");
    for (name, purpose) in TOOLS {
        let _ = writeln!(out, "- `{name}`: {purpose}");
    }

    let project = &board.project;
    if !project.document_prompt.is_empty() || !project.code_guidance.is_empty() {
        out.push_str(
            "\n## Project instructions\n\n\
             Set by the user. This is a snapshot; `project_get` always returns the current text.\n",
        );
        if !project.document_prompt.is_empty() {
            let _ = write!(
                out,
                "\n### Document generation\n\n{}\n",
                project.document_prompt
            );
        }
        if !project.code_guidance.is_empty() {
            let _ = write!(out, "\n### Code guidance\n\n{}\n", project.code_guidance);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn skill_has_frontmatter_and_every_tool() {
        let md = skill_markdown(&Board::new_default());
        assert!(md.starts_with("---\nname: stickynotes-board\ndescription: "));
        assert_eq!(md.matches("\n---\n").count(), 1, "frontmatter closes once");
        for (name, _) in TOOLS {
            assert!(md.contains(&format!("`{name}`")), "{name} missing");
        }
        assert!(md.contains("task_advance"));
        assert!(
            !md.contains("Project instructions"),
            "no section when unset"
        );
    }

    #[test]
    fn skill_includes_project_instructions() {
        let mut board = Board::new_default();
        board.project.document_prompt = "Write in plain English.".into();
        board.project.code_guidance = "Prefer small functions.".into();
        let md = skill_markdown(&board);
        assert!(md.contains("### Document generation\n\nWrite in plain English."));
        assert!(md.contains("### Code guidance\n\nPrefer small functions."));
    }

    #[test]
    fn skill_only_shows_sections_that_are_set() {
        let mut board = Board::new_default();
        board.project.code_guidance = "Use Rust.".into();
        let md = skill_markdown(&board);
        assert!(md.contains("### Code guidance"));
        assert!(!md.contains("### Document generation"));
    }

    #[test]
    fn instructions_point_agents_at_project_get() {
        let text = mcp_instructions();
        assert!(text.contains("project_get"));
        assert!(text.contains("task_advance"));
    }
}
