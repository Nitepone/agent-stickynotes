//! Core of agent-stickynotes: the board model, the commands that mutate it,
//! and the store that both the UI and the agent API share.
//!
//! This crate has no UI or network dependencies.

pub mod agent_guide;
pub mod command;
pub mod error;
pub mod export_md;
pub mod model;
pub mod ops;
pub mod persist;
pub mod project;
pub mod store;

pub use command::{Applied, Command, CriterionDraft, Origin, ReferenceDraft, TaskDraft, TaskPatch};
pub use error::{Error, Result};
pub use model::{
    AgentChange, Board, ChangeKind, Column, ColumnId, Criterion, Progress, ProjectSettings,
    Reference, Relation, Task, TaskId, card_text,
};
pub use store::{BoardStore, Change, Snapshot};
