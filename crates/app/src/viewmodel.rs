//! Conversion between core types and the JSON shapes the QML views use.
//! Kept free of Qt so it can be unit tested.

use serde::{Deserialize, Serialize};
use serde_json::json;
use stickynotes_core::model::SUGGESTED_DESCRIPTION_CHARS;
use stickynotes_core::{
    Applied, Board, CriterionDraft, Error, ReferenceDraft, Relation, Snapshot, Task, TaskDraft,
    TaskPatch, card_text,
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
    updated_at: String,
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
        updated_at: t.updated_at.to_rfc3339(),
    };
    serde_json::to_string(&vm).expect("view model serializes")
}

/// Project settings for `ProjectDialog.qml`.
pub fn project_json(board: &Board) -> String {
    json!({
        "title": board.title,
        "documentPrompt": board.project.document_prompt,
        "codeGuidance": board.project.code_guidance,
    })
    .to_string()
}

/// The relations a user can pick from: `[{value, label}]`.
pub fn relation_options_json() -> String {
    let options: Vec<_> = Relation::ALL
        .iter()
        .map(|r| json!({ "value": r.as_str(), "label": r.label() }))
        .collect();
    serde_json::Value::Array(options).to_string()
}

/// Shown in the window title, e.g. `Sprint 4 — sprint4.json •`.
pub fn window_title(s: &Snapshot) -> String {
    let file = s.path.as_ref().and_then(|p| p.file_name()).map_or_else(
        || "unsaved".to_string(),
        |n| n.to_string_lossy().into_owned(),
    );
    let dirty = if s.dirty { " •" } else { "" };
    format!("{} — {file}{dirty}", s.board.title)
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
    use stickynotes_core::{BoardStore, Command, Origin};

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
    fn window_title_marks_dirty() {
        let mut s = BoardStore::new(false).snapshot();
        assert_eq!(window_title(&s), "Untitled board — unsaved");
        s.dirty = true;
        s.path = Some("/tmp/x.json".into());
        assert_eq!(window_title(&s), "Untitled board — x.json •");
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

    #[test]
    fn project_json_carries_both_instructions() {
        let mut board = Board::new_default();
        board.project.document_prompt = "Be brief.".into();
        board.project.code_guidance = "Use Rust.".into();
        let v: serde_json::Value = serde_json::from_str(&project_json(&board)).unwrap();
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
