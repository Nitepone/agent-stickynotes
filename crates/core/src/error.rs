use std::path::PathBuf;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    #[error("{kind} {id} not found")]
    NotFound { kind: &'static str, id: String },

    #[error("invalid input: {0}")]
    Validation(String),

    #[error("agent write access is disabled; ask the user to enable it from the Agent menu")]
    AgentWriteDisabled,

    #[error("not permitted for agents: {0}")]
    AgentNotPermitted(String),

    #[error(
        "board changed (expected revision {expected}, current revision {actual}); re-read the board and retry"
    )]
    RevisionConflict { expected: u64, actual: u64 },

    #[error("column '{0}' is not empty; delete it with force to remove its tasks")]
    ColumnNotEmpty(String),

    #[error("{0} was modified by another program since it was loaded")]
    ModifiedOnDisk(PathBuf),

    #[error("the board has never been saved; create or open a project first")]
    NoPath,

    #[error("{0} is not a project folder: it has no stickynotes.json and is not empty")]
    NotAProject(PathBuf),

    #[error("unsupported board schema version {0}")]
    UnsupportedSchema(u32),

    #[error("I/O error on {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("invalid board file {path}: {source}")]
    Json {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
}

impl Error {
    pub fn not_found(kind: &'static str, id: impl std::fmt::Display) -> Self {
        Error::NotFound {
            kind,
            id: id.to_string(),
        }
    }
}

pub type Result<T, E = Error> = std::result::Result<T, E>;
