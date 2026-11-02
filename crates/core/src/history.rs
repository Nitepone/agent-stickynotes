//! Undo and redo of the user's own changes.
//!
//! Each change a user command makes is recorded as the entities it touched
//! (tasks, columns, board title, project settings) as they were before and
//! after. Undo restores the "before" copies, but only if the touched entities
//! still equal the "after" copies: if anything else changed them since (an
//! agent, or a later user edit), it refuses and leaves the history alone.
//! The history lives in memory only.

use std::collections::BTreeMap;

use crate::command::{Applied, Command};
use crate::error::{Error, Result};
use crate::model::{Board, Column, ColumnId, ProjectSettings, Task, TaskId};

/// Most steps kept; the oldest is dropped beyond this.
pub const MAX_STEPS: usize = 100;

/// A task and where it sits.
#[derive(Debug, Clone)]
pub struct Placed {
    pub task: Task,
    pub column: ColumnId,
    pub index: usize,
}

/// A column without its tasks, and where it sits.
#[derive(Debug, Clone)]
pub struct ColumnCopy {
    pub column: Column,
    pub index: usize,
}

/// The touched entities at one moment. `None` means "absent".
#[derive(Debug, Clone, Default)]
pub struct Snap {
    pub tasks: BTreeMap<TaskId, Option<Placed>>,
    pub columns: BTreeMap<ColumnId, Option<ColumnCopy>>,
    pub title: Option<String>,
    pub project: Option<ProjectSettings>,
}

impl Snap {
    pub fn is_empty(&self) -> bool {
        self.tasks.is_empty()
            && self.columns.is_empty()
            && self.title.is_none()
            && self.project.is_none()
    }
}

#[derive(Debug, Clone)]
pub struct Entry {
    pub label: String,
    before: Snap,
    after: Snap,
}

#[derive(Debug, Default)]
pub struct History {
    undo: Vec<Entry>,
    redo: Vec<Entry>,
}

impl History {
    pub fn clear(&mut self) {
        self.undo.clear();
        self.redo.clear();
    }

    pub fn labels(&self) -> (Option<String>, Option<String>) {
        (
            self.undo.last().map(|e| e.label.clone()),
            self.redo.last().map(|e| e.label.clone()),
        )
    }

    /// Record a user change from `before` to `after`; clears the redo stack.
    pub fn record(&mut self, cmd: &Command, applied: &Applied, before: &Board, after: &Board) {
        let (b, a) = diff(cmd, before, after);
        if b.is_empty() {
            return;
        }
        self.redo.clear();
        self.undo.push(Entry {
            label: label(cmd, applied, before, after),
            before: b,
            after: a,
        });
        if self.undo.len() > MAX_STEPS {
            self.undo.remove(0);
        }
    }

    /// The label and snapshot to restore for an undo, if the board still matches.
    pub fn plan_undo(&self, board: &Board) -> Result<(String, Snap)> {
        let e = self.undo.last().ok_or_else(|| nothing("undo"))?;
        check(board, &e.after, &e.before).map_err(|w| refused("undo", &w))?;
        Ok((e.label.clone(), e.before.clone()))
    }

    pub fn plan_redo(&self, board: &Board) -> Result<(String, Snap)> {
        let e = self.redo.last().ok_or_else(|| nothing("redo"))?;
        check(board, &e.before, &e.after).map_err(|w| refused("redo", &w))?;
        Ok((e.label.clone(), e.after.clone()))
    }

    pub fn finish_undo(&mut self) {
        if let Some(e) = self.undo.pop() {
            self.redo.push(e);
        }
    }

    pub fn finish_redo(&mut self) {
        if let Some(e) = self.redo.pop() {
            self.undo.push(e);
        }
    }
}

fn nothing(what: &str) -> Error {
    Error::Validation(format!("nothing to {what}"))
}

fn refused(what: &str, what_changed: &str) -> Error {
    Error::Validation(format!("Can't {what}: {what_changed} changed since"))
}

fn placed(board: &Board, id: TaskId) -> Option<Placed> {
    let (ci, ti) = board.locate_task(id)?;
    Some(Placed {
        task: board.columns[ci].tasks[ti].clone(),
        column: board.columns[ci].id,
        index: ti,
    })
}

fn column_copy(board: &Board, id: ColumnId) -> Option<ColumnCopy> {
    let index = board.column_index(id)?;
    let mut column = board.columns[index].clone();
    column.tasks.clear();
    Some(ColumnCopy { column, index })
}

/// Tasks compare by content and column; the index is ignored, because other
/// tasks coming and going shifts it.
fn same_task(a: &Option<Placed>, b: &Option<Placed>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(a), Some(b)) => a.task == b.task && a.column == b.column,
        _ => false,
    }
}

fn same_column(a: &Option<ColumnCopy>, b: &Option<ColumnCopy>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(a), Some(b)) => a.column == b.column && a.index == b.index,
        _ => false,
    }
}

/// The entities that differ between two boards, as before and after copies.
fn diff(cmd: &Command, before: &Board, after: &Board) -> (Snap, Snap) {
    let mut b = Snap::default();
    let mut a = Snap::default();
    let mut task_ids: Vec<TaskId> = before.tasks().map(|(_, t)| t.id).collect();
    task_ids.extend(after.tasks().map(|(_, t)| t.id));
    // A move within a column changes only an index, which equality ignores.
    let moved = match cmd {
        Command::MoveTask { id, .. } | Command::AdvanceTask { id } => Some(*id),
        _ => None,
    };
    for id in task_ids {
        let (x, y) = (placed(before, id), placed(after, id));
        if !same_task(&x, &y) || moved == Some(id) {
            b.tasks.insert(id, x);
            a.tasks.insert(id, y);
        }
    }
    let mut column_ids: Vec<ColumnId> = before.columns.iter().map(|c| c.id).collect();
    column_ids.extend(after.columns.iter().map(|c| c.id));
    for id in column_ids {
        let (x, y) = (column_copy(before, id), column_copy(after, id));
        if !same_column(&x, &y) {
            b.columns.insert(id, x);
            a.columns.insert(id, y);
        }
    }
    if before.title != after.title {
        b.title = Some(before.title.clone());
        a.title = Some(after.title.clone());
    }
    if before.project != after.project {
        b.project = Some(before.project.clone());
        a.project = Some(after.project.clone());
    }
    (b, a)
}

/// Whether the board still holds `expect` for every entity in it. On a
/// mismatch, says what changed ("#12", "column Review", ...). `target` is the
/// state about to be restored; it only supplies names for messages.
fn check(board: &Board, expect: &Snap, target: &Snap) -> std::result::Result<(), String> {
    for (id, want) in &expect.tasks {
        if !same_task(&placed(board, *id), want) {
            let number = want
                .as_ref()
                .or_else(|| target.tasks.get(id).and_then(Option::as_ref))
                .map(|p| p.task.number);
            return Err(number.map_or_else(|| "a task".into(), |n| format!("#{n}")));
        }
    }
    for (id, want) in &expect.columns {
        let title = || {
            want.as_ref()
                .or(target.columns.get(id).and_then(Option::as_ref))
                .map_or_else(
                    || "a column".into(),
                    |c| format!("column {}", c.column.title),
                )
        };
        if !same_column(&column_copy(board, *id), want) {
            return Err(title());
        }
        // A column about to disappear must not hold tasks we are not undoing.
        if target.columns.get(id).is_some_and(Option::is_none)
            && let Some(ci) = board.column_index(*id)
            && board.columns[ci]
                .tasks
                .iter()
                .any(|t| !expect.tasks.contains_key(&t.id))
        {
            return Err(title());
        }
    }
    if let Some(t) = &expect.title
        && *t != board.title
    {
        return Err("the board title".into());
    }
    if let Some(p) = &expect.project
        && *p != board.project
    {
        return Err("the project settings".into());
    }
    Ok(())
}

/// Put every entity in `snap` into the board. `next_number` is untouched.
pub fn restore(board: &mut Board, snap: &Snap) -> Result<()> {
    // Take out every touched task and every touched column that should go.
    for id in snap.tasks.keys() {
        if let Some((ci, ti)) = board.locate_task(*id) {
            board.columns[ci].tasks.remove(ti);
        }
    }
    for (id, copy) in &snap.columns {
        if copy.is_none()
            && let Some(ci) = board.column_index(*id)
        {
            board.columns.remove(ci);
        }
    }
    // Bring back or update the other columns, lowest position first.
    let mut cols: Vec<&ColumnCopy> = snap.columns.values().flatten().collect();
    cols.sort_by_key(|c| c.index);
    for copy in cols {
        let mut column = match board.column_index(copy.column.id) {
            Some(ci) => board.columns.remove(ci),
            None => copy.column.clone(),
        };
        column.title.clone_from(&copy.column.title);
        column.description.clone_from(&copy.column.description);
        column.extra.clone_from(&copy.column.extra);
        let at = copy.index.min(board.columns.len());
        board.columns.insert(at, column);
    }
    // Put the tasks back, lowest position first so each insert lands right.
    let mut tasks: Vec<&Placed> = snap.tasks.values().flatten().collect();
    tasks.sort_by_key(|p| p.index);
    for p in tasks {
        let ci = board.column_index(p.column).ok_or_else(|| {
            Error::Validation("Can't restore: the task's column no longer exists".into())
        })?;
        let list = &mut board.columns[ci].tasks;
        list.insert(p.index.min(list.len()), p.task.clone());
    }
    if let Some(t) = &snap.title {
        board.title.clone_from(t);
    }
    if let Some(p) = &snap.project {
        board.project.clone_from(p);
    }
    Ok(())
}

fn task_number(board: &Board, id: TaskId) -> String {
    board
        .task(id)
        .map_or_else(|| "task".into(), |t| format!("#{}", t.number))
}

fn column_title(board: &Board, id: ColumnId) -> String {
    board
        .column_index(id)
        .map_or_else(|| "column".into(), |i| board.columns[i].title.clone())
}

/// A short name for the change, e.g. "move #12 to Review".
fn label(cmd: &Command, applied: &Applied, before: &Board, after: &Board) -> String {
    match cmd {
        Command::CreateTask { .. } => match applied {
            Applied::Task(id) => format!("create {}", task_number(after, *id)),
            _ => "create task".into(),
        },
        Command::UpdateTask { id, .. } => format!("edit {}", task_number(after, *id)),
        Command::MoveTask { id, to_column, .. } => format!(
            "move {} to {}",
            task_number(after, *id),
            column_title(after, *to_column)
        ),
        Command::AdvanceTask { id } => {
            let col = after
                .locate_task(*id)
                .map_or_else(String::new, |(ci, _)| after.columns[ci].title.clone());
            format!("move {} to {col}", task_number(after, *id))
        }
        Command::DeleteTask { id } => format!("delete {}", task_number(before, *id)),
        Command::SetCriterion { task, done, .. } => format!(
            "{} criterion on {}",
            if *done { "tick" } else { "untick" },
            task_number(after, *task)
        ),
        Command::AttachArtifact { task, .. } => {
            format!("attach file to {}", task_number(after, *task))
        }
        Command::DetachArtifact { task, .. } => {
            format!("detach file from {}", task_number(after, *task))
        }
        Command::CreateColumn { .. } => match applied {
            Applied::Column(id) => format!("add column {}", column_title(after, *id)),
            _ => "add column".into(),
        },
        Command::UpdateColumn { id, .. } => format!("edit column {}", column_title(after, *id)),
        Command::MoveColumn { id, .. } => format!("move column {}", column_title(after, *id)),
        Command::DeleteColumn { id, .. } => format!("delete column {}", column_title(before, *id)),
        Command::RenameBoard { .. } => "rename board".into(),
        Command::UpdateProject { .. } => "edit project settings".into(),
        Command::Restore(_) => "restore".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::command::{Origin, TaskDraft, TaskPatch};
    use crate::store::BoardStore;
    use std::sync::Arc;

    fn make(store: &BoardStore, origin: Origin, text: &str) -> TaskId {
        let cmd = Command::CreateTask {
            column: None,
            position: None,
            draft: TaskDraft {
                description: text.into(),
                ..Default::default()
            },
        };
        match store.apply(origin, cmd, None).unwrap().0 {
            Applied::Task(id) => id,
            _ => unreachable!(),
        }
    }

    fn setup() -> (Arc<BoardStore>, TaskId, TaskId, TaskId) {
        let store = BoardStore::new(true);
        let ids = (
            make(&store, Origin::User, "a"),
            make(&store, Origin::User, "b"),
            make(&store, Origin::User, "c"),
        );
        (store, ids.0, ids.1, ids.2)
    }

    fn order(store: &BoardStore, col: usize) -> Vec<u64> {
        store.read(|b, _| b.columns[col].tasks.iter().map(|t| t.number).collect())
    }

    fn edit(id: TaskId, text: &str) -> Command {
        Command::UpdateTask {
            id,
            patch: TaskPatch {
                description: Some(text.into()),
                ..Default::default()
            },
        }
    }

    #[test]
    fn undo_and_redo_a_move_an_edit_and_a_delete() {
        let (store, a, b, _) = setup();
        let (col2, title2) = store.read(|b, _| (b.columns[1].id, b.columns[1].title.clone()));
        let mv = Command::MoveTask {
            id: a,
            to_column: col2,
            position: None,
        };
        store.apply(Origin::User, mv, None).unwrap();
        assert_eq!(
            store.history_labels().0.unwrap(),
            format!("move #1 to {title2}")
        );
        store.undo().unwrap();
        assert_eq!(order(&store, 0), [1, 2, 3]);
        store.redo().unwrap();
        assert_eq!(order(&store, 1), [1]);
        store.undo().unwrap();

        store.apply(Origin::User, edit(b, "changed"), None).unwrap();
        assert_eq!(store.history_labels().0.as_deref(), Some("edit #2"));
        store.undo().unwrap();
        let desc = store.read(|bd, _| bd.task(b).unwrap().description.clone());
        assert_eq!(desc, "b");

        store
            .apply(Origin::User, Command::DeleteTask { id: b }, None)
            .unwrap();
        assert_eq!(order(&store, 0), [1, 3]);
        let rev = store.revision();
        store.undo().unwrap();
        assert!(store.revision() > rev && store.snapshot().dirty);
        assert_eq!(order(&store, 0), [1, 2, 3], "number and position restored");
        make(&store, Origin::User, "d");
        assert_eq!(order(&store, 0), [1, 2, 3, 4], "numbers are never reused");
    }

    #[test]
    fn undoing_a_column_delete_restores_its_tasks() {
        let (store, a, _, _) = setup();
        let col = store.read(|b, _| b.columns[0].id);
        let before = store.snapshot().board;
        let del = Command::DeleteColumn {
            id: col,
            force: true,
        };
        store.apply(Origin::User, del, None).unwrap();
        assert!(store.read(|b, _| b.task(a).is_none()));
        store.undo().unwrap();
        assert_eq!(store.snapshot().board, before);
        store.redo().unwrap();
        assert!(store.read(|b, _| b.task(a).is_none()));
    }

    #[test]
    fn undo_refuses_after_an_agent_change_to_the_same_task_only() {
        let (store, a, b, _) = setup();
        store.apply(Origin::User, edit(a, "mine"), None).unwrap();
        store.apply(Origin::Agent, edit(b, "theirs"), None).unwrap();
        let rev = store.revision();
        store.undo().expect("a different task does not block");
        assert!(store.revision() > rev);
        store.redo().unwrap();

        store.apply(Origin::Agent, edit(a, "agent"), None).unwrap();
        let rev = store.revision();
        let err = store.undo().unwrap_err().to_string();
        assert!(err.contains("Can't undo: #1 changed since"), "{err}");
        assert_eq!(store.revision(), rev);
        assert_eq!(store.history_labels().0.as_deref(), Some("edit #1"));
        let desc = store.read(|bd, _| bd.task(a).unwrap().description.clone());
        assert_eq!(desc, "agent");
    }

    #[test]
    fn agent_changes_are_not_recorded_and_history_is_capped_and_cleared() {
        let store = BoardStore::new(true);
        make(&store, Origin::Agent, "x");
        assert_eq!(store.history_labels(), (None, None));
        for i in 0..MAX_STEPS + 5 {
            make(&store, Origin::User, &format!("t{i}"));
        }
        for _ in 0..MAX_STEPS {
            store.undo().unwrap();
        }
        assert!(store.undo().is_err(), "only 100 steps are kept");
        assert_eq!(store.read(|b, _| b.tasks().count()), 6);
        // A new change clears redo.
        make(&store, Origin::User, "new");
        assert!(store.history_labels().1.is_none());
        store.clear_history();
        assert_eq!(store.history_labels(), (None, None));
    }
}
