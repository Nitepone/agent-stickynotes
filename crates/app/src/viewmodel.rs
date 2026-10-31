//! Conversion between core types and the JSON shapes the QML views use.
//! Kept free of Qt so it can be unit tested.

use std::path::Path;

use serde::{Deserialize, Serialize};
use serde_json::json;
use stickynotes_core::model::SUGGESTED_DESCRIPTION_CHARS;
use stickynotes_core::project;
use stickynotes_core::{
    Applied, ArtifactFile, ArtifactKind, Board, BoardStore, CriterionDraft, Error, ReferenceDraft,
    Relation, Snapshot, Task, TaskDraft, TaskPatch, artifact, card_text,
};
use uuid::Uuid;

use crate::drafting::{Draft, DraftError, DraftOptions, DraftRequest};

/// Most lines of description shown on a card before `[...]`.
const CARD_MAX_LINES: usize = 6;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BoardVm<'a> {
    title: &'a str,
    columns: Vec<ColumnVm<'a>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ColumnVm<'a> {
    id: Uuid,
    title: &'a str,
    description: &'a str,
    tasks: Vec<CardVm>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CardVm {
    id: Uuid,
    number: u64,
    /// Set when an agent made the latest change: `{at: ms since epoch, kind}`.
    agent_change: Option<AgentChangeVm>,
    card_text: String,
    done: usize,
    total: usize,
    artifact_count: usize,
}

#[derive(Serialize)]
struct AgentChangeVm {
    at: i64,
    kind: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TaskVm<'a> {
    id: Uuid,
    number: u64,
    column_id: Uuid,
    description: &'a str,
    extended_description: &'a str,
    requirements: &'a [String],
    criteria: Vec<CriterionVm<'a>>,
    references: Vec<ReferenceVm<'a>>,
    artifacts: Vec<ArtifactVm<'a>>,
    updated_at: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ArtifactVm<'a> {
    id: Uuid,
    name: &'a str,
    kind: &'static str,
    by_agent: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ReferenceVm<'a> {
    task_id: Uuid,
    relation: &'static str,
    relation_label: &'static str,
    description: &'a str,
    column_title: &'a str,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CriterionVm<'a> {
    id: Uuid,
    text: &'a str,
    done: bool,
}

/// The board as rendered by `BoardView.qml`.
pub fn board_json(board: &Board) -> String {
    let vm = BoardVm {
        title: &board.title,
        columns: board
            .columns
            .iter()
            .map(|c| ColumnVm {
                id: c.id,
                title: &c.title,
                description: &c.description,
                tasks: c.tasks.iter().map(card).collect(),
            })
            .collect(),
    };
    serde_json::to_string(&vm).expect("view model serializes")
}

fn card(task: &Task) -> CardVm {
    let p = task.progress();
    CardVm {
        id: task.id,
        number: task.number,
        agent_change: task.agent_change.as_ref().map(|c| AgentChangeVm {
            at: c.at.timestamp_millis(),
            kind: c.kind.as_str(),
        }),
        card_text: card_text(
            &task.description,
            SUGGESTED_DESCRIPTION_CHARS,
            CARD_MAX_LINES,
        ),
        done: p.done,
        total: p.total,
        artifact_count: task.artifacts.len(),
    }
}

/// Full task for `TaskDialog.qml`, or `""` if it no longer exists.
pub fn task_json(board: &Board, id: Uuid) -> String {
    let Some((ci, ti)) = board.locate_task(id) else {
        return String::new();
    };
    let t = &board.columns[ci].tasks[ti];
    let vm = TaskVm {
        id: t.id,
        number: t.number,
        column_id: board.columns[ci].id,
        description: &t.description,
        extended_description: &t.extended_description,
        requirements: &t.requirements,
        criteria: t
            .acceptance_criteria
            .iter()
            .map(|c| CriterionVm {
                id: c.id,
                text: &c.text,
                done: c.done,
            })
            .collect(),
        references: t
            .references
            .iter()
            .filter_map(|r| {
                let (oc, ot) = board.locate_task(r.task)?;
                Some(ReferenceVm {
                    task_id: r.task,
                    relation: r.relation.as_str(),
                    relation_label: r.relation.label(),
                    description: &board.columns[oc].tasks[ot].description,
                    column_title: &board.columns[oc].title,
                })
            })
            .collect(),
        artifacts: t
            .artifacts
            .iter()
            .map(|a| ArtifactVm {
                id: a.id,
                name: &a.name,
                kind: a.kind.as_str(),
                by_agent: a.by_agent,
            })
            .collect(),
        updated_at: t.updated_at.to_rfc3339(),
    };
    serde_json::to_string(&vm).expect("view model serializes")
}

/// Project settings for `ProjectDialog.qml`, with every file in the
/// project's `artifacts/` folder and the tasks each is attached to.
pub fn project_json(board: &Board, files: &[ArtifactFile]) -> String {
    let artifacts: Vec<_> = files
        .iter()
        .map(|f| {
            json!({
                "name": f.file.name,
                "kind": f.file.kind.as_str(),
                "size": f.file.size,
                "tasks": f.tasks.iter().map(|(_, number, _)| number).collect::<Vec<_>>(),
            })
        })
        .collect();
    json!({
        "title": board.title,
        "documentPrompt": board.project.document_prompt,
        "codeGuidance": board.project.code_guidance,
        "artifacts": artifacts,
    })
    .to_string()
}

/// Every file in `artifacts/` for the artifacts page, newest first:
/// `[{name, kind, size, at (ms), tasks: [{id, number}]}]`.
pub fn artifacts_json(files: &[ArtifactFile]) -> String {
    let mut sorted: Vec<&ArtifactFile> = files.iter().collect();
    sorted.sort_by(|a, b| {
        b.at_ms
            .cmp(&a.at_ms)
            .then_with(|| a.file.name.cmp(&b.file.name))
    });
    let list: Vec<_> = sorted
        .into_iter()
        .map(|f| {
            let mut tasks: Vec<_> = f.tasks.iter().collect();
            tasks.sort_by_key(|(_, number, _)| *number);
            json!({
                "name": f.file.name,
                "kind": f.file.kind.as_str(),
                "size": f.file.size,
                "at": f.at_ms,
                "tasks": tasks
                    .iter()
                    .map(|(id, number, _)| json!({ "id": id.to_string(), "number": number }))
                    .collect::<Vec<_>>(),
            })
        })
        .collect();
    serde_json::Value::Array(list).to_string()
}

/// What `ArtifactViewer.qml` shows for a file in `artifacts/`: Markdown comes
/// with its text, images with the path of the file.
pub fn artifact_json(store: &BoardStore, name: &str) -> String {
    let shown = store.artifact_path(name).and_then(|path| {
        let kind = artifact::kind_of(name).ok_or_else(|| {
            Error::Validation(format!("'{name}' is not a Markdown or image file"))
        })?;
        let text = match kind {
            ArtifactKind::Markdown => {
                Some(String::from_utf8_lossy(&store.read_artifact(name)?).into_owned())
            }
            ArtifactKind::Image => None,
        };
        let html = text.as_deref().map(crate::markdown::to_html);
        Ok(json!({
            "ok": true,
            "name": name,
            "kind": kind.as_str(),
            "text": text,
            "html": html,
            "path": path.to_string_lossy(),
        }))
    });
    match shown {
        Ok(value) => value.to_string(),
        Err(e) => error_json(&e.to_string()),
    }
}

/// The relations a user can pick from: `[{value, label}]`.
pub fn relation_options_json() -> String {
    let options: Vec<_> = Relation::ALL
        .iter()
        .map(|r| json!({ "value": r.as_str(), "label": r.label() }))
        .collect();
    serde_json::Value::Array(options).to_string()
}

/// The projects folder and what is in it, for the project picker:
/// `{root, projects: [{dir, title, current}]}`.
pub fn projects_json(root: &Path, current: Option<&Path>) -> String {
    let projects: Vec<_> = project::list_projects(root)
        .into_iter()
        .map(|p| {
            json!({
                "dir": p.dir.to_string_lossy(),
                "title": p.title,
                "current": current == Some(p.dir.as_path()),
            })
        })
        .collect();
    json!({ "root": root.to_string_lossy(), "projects": projects }).to_string()
}

/// Shown in the window title, e.g. `Agent Stickynotes - Sprint 4 •`: the
/// board's title, and a dot while there are unsaved changes.
pub fn window_title(s: &Snapshot) -> String {
    let dirty = if s.dirty { " •" } else { "" };
    format!("Agent Stickynotes - {}{dirty}", s.board.title)
}

/// What `TaskDialog.qml` submits.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskForm {
    description: String,
    #[serde(default)]
    extended_description: String,
    #[serde(default)]
    requirements: Vec<String>,
    #[serde(default)]
    criteria: Vec<CriterionForm>,
    /// Absent when creating a task: links need an existing task.
    #[serde(default)]
    references: Option<Vec<ReferenceForm>>,
}

#[derive(Deserialize)]
pub struct ReferenceForm {
    task: Uuid,
    relation: Relation,
}

#[derive(Deserialize)]
pub struct CriterionForm {
    /// Empty or missing for criteria added in the dialog.
    #[serde(default)]
    id: String,
    text: String,
    #[serde(default)]
    done: bool,
}

impl TaskForm {
    /// What to ask a drafting backend about this (possibly unsaved) task.
    pub fn draft_request(
        &self,
        document_prompt: &str,
        code_guidance: &str,
        options: DraftOptions,
    ) -> Result<DraftRequest, String> {
        if self.description.trim().is_empty() {
            return Err("Write a description first; the draft is based on it.".into());
        }
        let texts = |items: Vec<&str>| {
            items
                .into_iter()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(String::from)
                .collect()
        };
        Ok(DraftRequest {
            description: self.description.trim().to_string(),
            extended_description: self.extended_description.trim().to_string(),
            requirements: texts(self.requirements.iter().map(String::as_str).collect()),
            acceptance_criteria: texts(self.criteria.iter().map(|c| c.text.as_str()).collect()),
            document_prompt: document_prompt.to_string(),
            code_guidance: code_guidance.to_string(),
            options,
        })
    }

    pub fn parse(json: &str) -> Result<Self, String> {
        serde_json::from_str(json).map_err(|e| format!("malformed task form: {e}"))
    }

    pub fn into_draft(self) -> TaskDraft {
        TaskDraft {
            description: self.description,
            extended_description: self.extended_description,
            requirements: self.requirements,
            acceptance_criteria: criterion_drafts(self.criteria),
        }
    }

    pub fn into_patch(self) -> TaskPatch {
        TaskPatch {
            description: Some(self.description),
            extended_description: Some(self.extended_description),
            requirements: Some(self.requirements),
            acceptance_criteria: Some(criterion_drafts(self.criteria)),
            references: self.references.map(|refs| {
                refs.into_iter()
                    .map(|r| ReferenceDraft {
                        task: r.task,
                        relation: r.relation,
                    })
                    .collect()
            }),
        }
    }
}

fn criterion_drafts(criteria: Vec<CriterionForm>) -> Vec<CriterionDraft> {
    criteria
        .into_iter()
        .map(|c| CriterionDraft {
            id: Uuid::parse_str(&c.id).ok(),
            text: c.text,
            done: c.done,
        })
        .collect()
}

/// Result object returned by controller invokables: `{ok, id?}` or
/// `{ok: false, code, message}`.
pub fn result_json(result: Result<Option<Applied>, Error>) -> String {
    let value = match result {
        Ok(applied) => {
            let id = match applied {
                Some(Applied::Task(id) | Applied::Column(id)) => Some(id.to_string()),
                _ => None,
            };
            json!({ "ok": true, "id": id })
        }
        Err(e) => json!({ "ok": false, "code": error_code(&e), "message": e.to_string() }),
    };
    value.to_string()
}

/// Outcome of a drafting run, for `TaskDialog.qml`. On success only items the
/// task does not already have are included.
pub fn draft_result_json(
    result: Result<Draft, DraftError>,
    request: &DraftRequest,
    backend: &str,
) -> String {
    let value = match result {
        Ok(draft) => {
            let draft = draft.without_existing(request);
            json!({
                "ok": true,
                "backend": backend,
                "requirements": draft.requirements,
                "criteria": draft.acceptance_criteria,
            })
        }
        Err(e) => json!({ "ok": false, "code": e.code(), "message": e.to_string() }),
    };
    value.to_string()
}

pub fn error_json(message: &str) -> String {
    json!({ "ok": false, "code": "error", "message": message }).to_string()
}

fn error_code(e: &Error) -> &'static str {
    match e {
        Error::ColumnNotEmpty(_) => "column_not_empty",
        Error::ModifiedOnDisk(_) => "modified_on_disk",
        Error::NoPath => "no_path",
        Error::Validation(_) => "validation",
        Error::NotFound { .. } => "not_found",
        _ => "error",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use stickynotes_core::{Applied, BoardStore, Command, Origin, TaskDraft};

    #[test]
    fn board_json_has_card_text_and_progress() {
        let store = BoardStore::new(false);
        let form = TaskForm::parse(&format!(
            r#"{{"description":"{}","criteria":[{{"text":"a","done":true}},{{"text":"b"}}]}}"#,
            "word ".repeat(60)
        ))
        .unwrap();
        store
            .apply(
                Origin::User,
                Command::CreateTask {
                    column: None,
                    position: None,
                    draft: form.into_draft(),
                },
                None,
            )
            .unwrap();
        let json: serde_json::Value =
            serde_json::from_str(&store.read(|b, _| board_json(b))).unwrap();
        let card = &json["columns"][0]["tasks"][0];
        assert!(card["cardText"].as_str().unwrap().ends_with("[...]"));
        assert_eq!(card["number"], 1);
        assert_eq!(card["done"], 1);
        assert_eq!(card["total"], 2);
    }

    #[test]
    fn form_keeps_existing_criterion_ids() {
        let id = Uuid::new_v4();
        let form = TaskForm::parse(&format!(
            r#"{{"description":"d","criteria":[{{"id":"{id}","text":"x"}},{{"id":"","text":"y"}}]}}"#
        ))
        .unwrap();
        let patch = form.into_patch();
        let criteria = patch.acceptance_criteria.unwrap();
        assert_eq!(criteria[0].id, Some(id));
        assert_eq!(criteria[1].id, None);
    }

    #[test]
    fn result_json_reports_codes() {
        let v: serde_json::Value =
            serde_json::from_str(&result_json(Err(Error::ColumnNotEmpty("x".into())))).unwrap();
        assert_eq!(v["ok"], false);
        assert_eq!(v["code"], "column_not_empty");
    }

    #[test]
    fn projects_json_lists_projects_and_marks_the_current_one() {
        let root = tempfile::tempdir().unwrap();
        let store = BoardStore::new(false);
        let dir = root.path().join("demo");
        store.create_project(&dir, "Demo").unwrap();
        let value: serde_json::Value =
            serde_json::from_str(&projects_json(root.path(), Some(&dir))).unwrap();
        assert_eq!(value["projects"][0]["title"], "Demo");
        assert_eq!(value["projects"][0]["current"], true);
        assert_eq!(value["root"], root.path().to_string_lossy().as_ref());
    }

    #[test]
    fn window_title_marks_dirty() {
        let mut s = BoardStore::new(false).snapshot();
        assert_eq!(window_title(&s), "Agent Stickynotes - Untitled board");
        s.dirty = true;
        assert_eq!(window_title(&s), "Agent Stickynotes - Untitled board •");
    }

    #[test]
    fn task_json_lists_references_with_labels() {
        use stickynotes_core::{Command, Origin};
        let store = BoardStore::new(false);
        let mut ids = Vec::new();
        for d in ["one", "two"] {
            let form = TaskForm::parse(&format!(r#"{{"description":"{d}"}}"#)).unwrap();
            let (applied, _) = store
                .apply(
                    Origin::User,
                    Command::CreateTask {
                        column: None,
                        position: None,
                        draft: form.into_draft(),
                    },
                    None,
                )
                .unwrap();
            let Applied::Task(id) = applied else { panic!() };
            ids.push(id);
        }
        let form = TaskForm::parse(&format!(
            r#"{{"description":"one","references":[{{"task":"{}","relation":"blocks"}}]}}"#,
            ids[1]
        ))
        .unwrap();
        store
            .apply(
                Origin::User,
                Command::UpdateTask {
                    id: ids[0],
                    patch: form.into_patch(),
                },
                None,
            )
            .unwrap();

        let json: serde_json::Value =
            serde_json::from_str(&store.read(|b, _| task_json(b, ids[1]))).unwrap();
        let r = &json["references"][0];
        assert_eq!(r["taskId"], ids[0].to_string());
        assert_eq!(r["relation"], "blocked_by");
        assert_eq!(r["relationLabel"], "is blocked by");
        assert_eq!(r["description"], "one");
        assert_eq!(r["columnTitle"], "Backlog");
    }

    #[test]
    fn form_without_references_does_not_touch_them() {
        let patch = TaskForm::parse(r#"{"description":"d"}"#)
            .unwrap()
            .into_patch();
        assert!(patch.references.is_none());
        assert!(
            TaskForm::parse(
                r#"{"description":"d","references":[{"task":"nope","relation":"blocks"}]}"#
            )
            .is_err()
        );
    }

    #[test]
    fn relation_options_cover_every_relation() {
        let v: serde_json::Value = serde_json::from_str(&relation_options_json()).unwrap();
        assert_eq!(v.as_array().unwrap().len(), Relation::ALL.len());
        assert_eq!(
            v[1],
            json!({"value": "blocked_by", "label": "is blocked by"})
        );
    }

    /// A project store with one task that has a Markdown and a PNG artifact.
    fn store_with_artifacts() -> (tempfile::TempDir, std::sync::Arc<BoardStore>, Uuid) {
        let root = tempfile::tempdir().unwrap();
        let store = BoardStore::new(true);
        store.create_project(&root.path().join("p"), "P").unwrap();
        let (applied, _) = store
            .apply(
                Origin::User,
                Command::CreateTask {
                    column: None,
                    position: None,
                    draft: TaskDraft {
                        description: "T".into(),
                        ..Default::default()
                    },
                },
                None,
            )
            .unwrap();
        let Applied::Task(id) = applied else { panic!() };
        store
            .add_artifact(Origin::Agent, id, "plan.md", b"# Plan\n\ntext", None)
            .unwrap();
        store
            .add_artifact(Origin::User, id, "x.png", b"\x89PNG\r\n\x1a\n..", None)
            .unwrap();
        (root, store, id)
    }

    #[test]
    fn cards_and_the_task_dialog_know_the_artifacts() {
        let (_root, store, id) = store_with_artifacts();
        let snap = store.snapshot();
        let board: serde_json::Value = serde_json::from_str(&board_json(&snap.board)).unwrap();
        assert_eq!(board["columns"][0]["tasks"][0]["artifactCount"], 2);

        let task: serde_json::Value = serde_json::from_str(&task_json(&snap.board, id)).unwrap();
        assert_eq!(task["artifacts"][0]["name"], "plan.md");
        assert_eq!(task["artifacts"][0]["kind"], "markdown");
        assert_eq!(task["artifacts"][0]["byAgent"], true);
        assert_eq!(task["artifacts"][1]["kind"], "image");
        assert_eq!(task["artifacts"][1]["byAgent"], false);
    }

    #[test]
    fn project_json_lists_files_and_where_they_are_attached() {
        let (_root, store, _) = store_with_artifacts();
        // A file nothing points at.
        std::fs::write(store.project_dir().unwrap().join("artifacts/loose.md"), "x").unwrap();
        let files = store.artifact_files();
        let v: serde_json::Value =
            serde_json::from_str(&store.read(|b, _| project_json(b, &files))).unwrap();
        let names: Vec<_> = v["artifacts"]
            .as_array()
            .unwrap()
            .iter()
            .map(|a| (a["name"].as_str().unwrap(), a["tasks"].clone()))
            .collect();
        assert_eq!(
            names,
            [
                ("loose.md", json!([])),
                ("plan.md", json!([1])),
                ("x.png", json!([1]))
            ]
        );
    }

    #[test]
    fn artifacts_json_lists_newest_first_with_task_ids() {
        let (_root, store, _) = store_with_artifacts();
        std::fs::write(store.project_dir().unwrap().join("artifacts/loose.md"), "x").unwrap();
        let mut files = store.artifact_files();
        // Pin the times: attached files use the moment they were attached.
        for f in &mut files {
            f.at_ms = match f.file.name.as_str() {
                "loose.md" => 3_000,
                "plan.md" => 1_000,
                _ => 2_000,
            };
        }
        let v: serde_json::Value = serde_json::from_str(&artifacts_json(&files)).unwrap();
        let names: Vec<_> = v
            .as_array()
            .unwrap()
            .iter()
            .map(|a| a["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, ["loose.md", "x.png", "plan.md"]);
        assert_eq!(v[0]["tasks"], json!([]));
        assert_eq!(v[2]["at"], 1_000);
        assert_eq!(v[2]["kind"], "markdown");
        assert_eq!(v[2]["tasks"][0]["number"], 1);
        let id = v[2]["tasks"][0]["id"].as_str().unwrap();
        assert!(store.read(|b, _| b.tasks().any(|(_, t)| t.id.to_string() == id)));
    }

    #[test]
    fn attached_files_are_dated_by_the_attachment_and_loose_ones_by_the_file() {
        let (_root, store, _) = store_with_artifacts();
        std::fs::write(store.project_dir().unwrap().join("artifacts/loose.md"), "x").unwrap();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64;
        for f in store.artifact_files() {
            assert!(
                (now - f.at_ms).abs() < 60_000,
                "{} is dated {}",
                f.file.name,
                f.at_ms
            );
            if f.tasks.is_empty() {
                assert_eq!(f.at_ms, f.file.modified_ms);
            }
        }
    }

    #[test]
    fn viewer_gets_text_for_markdown_and_a_path_for_images() {
        let (_root, store, _) = store_with_artifacts();
        let md: serde_json::Value =
            serde_json::from_str(&artifact_json(&store, "plan.md")).unwrap();
        assert_eq!(md["ok"], true);
        assert_eq!(md["kind"], "markdown");
        assert_eq!(md["text"], "# Plan\n\ntext");
        assert!(md["html"].as_str().unwrap().contains("<h1>Plan</h1>"));

        let img: serde_json::Value = serde_json::from_str(&artifact_json(&store, "x.png")).unwrap();
        assert_eq!(img["kind"], "image");
        assert!(img["text"].is_null());
        assert!(img["path"].as_str().unwrap().ends_with("artifacts/x.png"));

        for bad in ["../stickynotes.json", "missing.md", "stickynotes.json", ""] {
            let v: serde_json::Value = serde_json::from_str(&artifact_json(&store, bad)).unwrap();
            assert_eq!(v["ok"], false, "{bad}");
        }
    }

    #[test]
    fn project_json_carries_both_instructions() {
        let mut board = Board::new_default();
        board.project.document_prompt = "Be brief.".into();
        board.project.code_guidance = "Use Rust.".into();
        let v: serde_json::Value = serde_json::from_str(&project_json(&board, &[])).unwrap();
        assert_eq!(v["documentPrompt"], "Be brief.");
        assert_eq!(v["codeGuidance"], "Use Rust.");
        assert_eq!(v["title"], "Untitled board");
    }

    #[test]
    fn draft_request_comes_from_the_form_and_needs_a_description() {
        let form = TaskForm::parse(
            r#"{"description":" Add login ","extendedDescription":"Email","requirements":["Use HTTPS",""],
                "criteria":[{"id":"","text":"Can sign in"},{"id":"","text":" "}]}"#,
        )
        .unwrap();
        let options = DraftOptions {
            system_prompt: "Be brief.".into(),
            model: "opus".into(),
            effort: "high".into(),
        };
        let req = form
            .draft_request("Plain.", "Rust.", options.clone())
            .unwrap();
        assert_eq!(req.options, options);
        assert_eq!(req.description, "Add login");
        assert_eq!(req.extended_description, "Email");
        assert_eq!(req.requirements, ["Use HTTPS"]);
        assert_eq!(req.acceptance_criteria, ["Can sign in"]);
        assert_eq!(
            (req.document_prompt.as_str(), req.code_guidance.as_str()),
            ("Plain.", "Rust.")
        );

        let blank = TaskForm::parse(r#"{"description":"  "}"#).unwrap();
        assert!(
            blank
                .draft_request("", "", DraftOptions::default())
                .is_err()
        );
    }

    #[test]
    fn draft_result_json_keeps_only_new_items_or_reports_the_error() {
        let request = DraftRequest {
            description: "d".into(),
            requirements: vec!["Use HTTPS".into()],
            ..Default::default()
        };
        let draft = Draft {
            requirements: vec!["use https".into(), "Hash passwords".into()],
            acceptance_criteria: vec!["Can sign in".into()],
        };
        let v: serde_json::Value =
            serde_json::from_str(&draft_result_json(Ok(draft), &request, "Claude Code")).unwrap();
        assert_eq!(v["ok"], true);
        assert_eq!(v["requirements"], json!(["Hash passwords"]));
        assert_eq!(v["criteria"], json!(["Can sign in"]));
        assert_eq!(v["backend"], "Claude Code");

        let v: serde_json::Value = serde_json::from_str(&draft_result_json(
            Err(DraftError::Unavailable("not installed".into())),
            &request,
            "Claude Code",
        ))
        .unwrap();
        assert_eq!(v["ok"], false);
        assert_eq!(v["code"], "unavailable");
        assert_eq!(v["message"], "not installed");
    }

    #[test]
    fn cards_carry_the_agent_change_only_when_there_is_one() {
        use stickynotes_core::{Command, Origin};
        let store = BoardStore::new(true);
        let create = |origin| {
            store
                .apply(
                    origin,
                    Command::CreateTask {
                        column: None,
                        position: None,
                        draft: TaskForm::parse(r#"{"description":"t"}"#)
                            .unwrap()
                            .into_draft(),
                    },
                    None,
                )
                .unwrap();
        };
        create(Origin::User);
        create(Origin::Agent);
        let json: serde_json::Value =
            serde_json::from_str(&store.read(|b, _| board_json(b))).unwrap();
        let tasks = &json["columns"][0]["tasks"];
        assert!(
            tasks[0]["agentChange"].is_null(),
            "the user's own task is not marked"
        );
        assert_eq!(tasks[1]["agentChange"]["kind"], "created");
        assert!(tasks[1]["agentChange"]["at"].as_i64().unwrap() > 1_700_000_000_000);
    }
}
