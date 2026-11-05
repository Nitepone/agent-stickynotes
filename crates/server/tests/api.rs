use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use rmcp::ServiceExt;
use rmcp::model::{CallToolRequestParams, ReadResourceRequestParams};
use rmcp::transport::StreamableHttpClientTransport;
use rmcp::transport::streamable_http_client::StreamableHttpClientTransportConfig;
use serde_json::{Value, json};
use stickynotes_core::{BoardStore, Command, Origin, agent_guide};
use tokio_util::sync::CancellationToken;
use tower::ServiceExt as _;

const TOKEN: &str = "test-token";

struct Api {
    store: Arc<BoardStore>,
    app: axum::Router,
}

impl Api {
    fn new(agent_write: bool) -> Self {
        let store = BoardStore::new(agent_write);
        let app = stickynotes_server::router(store.clone(), TOKEN.into(), CancellationToken::new());
        Api { store, app }
    }

    /// An API whose board is saved in a fresh project folder (needed for artifacts).
    fn in_project() -> (tempfile::TempDir, Self) {
        let api = Api::new(true);
        let root = tempfile::tempdir().unwrap();
        api.store
            .create_project(&root.path().join("p"), "P")
            .unwrap();
        (root, api)
    }

    async fn call(&self, method: &str, uri: &str, body: Option<Value>) -> (StatusCode, Value) {
        self.call_with(method, uri, body, Some(TOKEN), None).await
    }

    async fn call_with(
        &self,
        method: &str,
        uri: &str,
        body: Option<Value>,
        token: Option<&str>,
        if_match: Option<u64>,
    ) -> (StatusCode, Value) {
        let mut req = Request::builder()
            .method(method)
            .uri(format!("/api/v1{uri}"))
            .header("content-type", "application/json");
        if let Some(t) = token {
            req = req.header("authorization", format!("Bearer {t}"));
        }
        if let Some(rev) = if_match {
            req = req.header("if-match", rev.to_string());
        }
        let body = body.map_or_else(Body::empty, |b| Body::from(b.to_string()));
        let res = self
            .app
            .clone()
            .oneshot(req.body(body).unwrap())
            .await
            .unwrap();
        let status = res.status();
        let bytes = res.into_body().collect().await.unwrap().to_bytes();
        let value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
        (status, value)
    }
}

#[tokio::test]
async fn requires_token() {
    let api = Api::new(true);
    let (status, _) = api.call_with("GET", "/board", None, None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = api
        .call_with("GET", "/board", None, Some("wrong"), None)
        .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, board) = api.call("GET", "/board", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(board["columns"].as_array().unwrap().len(), 5);
}

#[tokio::test]
async fn category_is_set_matched_and_cleared_over_rest() {
    let api = Api::new(true);
    let (status, a) = api
        .call(
            "POST",
            "/tasks",
            Some(json!({"description": "A", "category": " UI "})),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(a["category"], "UI");
    let (_, b) = api
        .call("POST", "/tasks", Some(json!({"description": "B"})))
        .await;
    assert!(b["category"].is_null());
    let uri = format!("/tasks/{}", b["id"].as_str().unwrap());

    let (status, b) = api
        .call("PATCH", &uri, Some(json!({"category": "ui"})))
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(b["category"], "UI", "existing spelling wins");

    let (_, b) = api
        .call("PATCH", &uri, Some(json!({"description": "B2"})))
        .await;
    assert_eq!(b["category"], "UI", "omitted leaves it alone");

    let (_, b) = api.call("PATCH", &uri, Some(json!({"category": ""}))).await;
    assert!(b["category"].is_null());

    let (status, _) = api
        .call("PATCH", &uri, Some(json!({"category": "x".repeat(41)})))
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn task_lifecycle() {
    let api = Api::new(true);
    let (status, task) = api
        .call(
            "POST",
            "/tasks",
            Some(json!({"description": "Write docs", "acceptance_criteria": ["README exists"]})),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED);
    let id = task["id"].as_str().unwrap().to_string();
    assert_eq!(task["column"]["title"], "Backlog");
    assert_eq!(task["next_column"]["title"], "To Do");

    let cid = task["acceptance_criteria"][0]["id"].as_str().unwrap();
    let (status, task) = api
        .call(
            "PUT",
            &format!("/tasks/{id}/criteria/{cid}"),
            Some(json!({"done": true})),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(task["progress"], json!({"done": 1, "total": 1}));

    let (status, task) = api
        .call("POST", &format!("/tasks/{id}/advance"), None)
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(task["column"]["title"], "To Do");

    let (status, task) = api
        .call(
            "PATCH",
            &format!("/tasks/{id}"),
            Some(json!({"extended_description": "more"})),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(task["extended_description"], "more");
    assert_eq!(task["description"], "Write docs");

    let (status, list) = api.call("GET", "/tasks?column=to%20do", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 1);

    let (status, _) = api.call("DELETE", &format!("/tasks/{id}"), None).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = api.call("GET", &format!("/tasks/{id}"), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn writes_forbidden_when_disabled() {
    let api = Api::new(false);
    let (status, err) = api
        .call("POST", "/tasks", Some(json!({"description": "x"})))
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(err["error"], "agent_write_disabled");

    api.store.set_agent_write(true);
    let (status, _) = api
        .call("POST", "/tasks", Some(json!({"description": "x"})))
        .await;
    assert_eq!(status, StatusCode::CREATED);
}

#[tokio::test]
async fn stale_revision_conflicts() {
    let api = Api::new(true);
    let rev = api.store.revision();
    let body = Some(json!({"description": "x"}));
    let (status, _) = api
        .call_with("POST", "/tasks", body.clone(), Some(TOKEN), Some(rev))
        .await;
    assert_eq!(status, StatusCode::CREATED);
    let (status, err) = api
        .call_with("POST", "/tasks", body, Some(TOKEN), Some(rev))
        .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(err["error"], "revision_conflict");
}

#[tokio::test]
async fn references_are_mirrored() {
    let api = Api::new(true);
    let mut ids = Vec::new();
    for d in ["Build the API", "Write the docs"] {
        let (_, t) = api
            .call("POST", "/tasks", Some(json!({"description": d})))
            .await;
        ids.push(t["id"].as_str().unwrap().to_string());
    }
    let (status, a) = api
        .call(
            "PATCH",
            &format!("/tasks/{}", ids[0]),
            Some(json!({"references": [{"task_id": ids[1], "relation": "blocks"}]})),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(a["references"][0]["relation"], "blocks");
    assert_eq!(a["references"][0]["description"], "Write the docs");

    let (_, b) = api.call("GET", &format!("/tasks/{}", ids[1]), None).await;
    assert_eq!(b["references"][0]["relation"], "blocked_by");
    assert_eq!(b["references"][0]["task_id"], ids[0].as_str());

    let (status, err) = api
        .call(
            "PATCH",
            &format!("/tasks/{}", ids[0]),
            Some(json!({"references": [{"task_id": ids[1], "relation": "likes"}]})),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(err["message"].as_str().unwrap().contains("blocked_by"));

    let (status, _) = api
        .call(
            "PATCH",
            &format!("/tasks/{}", ids[0]),
            Some(json!({"references": [{"task_id": ids[0], "relation": "blocks"}]})),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    api.call("DELETE", &format!("/tasks/{}", ids[0]), None)
        .await;
    let (_, b) = api.call("GET", &format!("/tasks/{}", ids[1]), None).await;
    assert_eq!(b["references"], json!([]));
}

#[tokio::test]
async fn project_settings_are_readable_but_not_writable_by_agents() {
    let api = Api::new(true);
    let (status, p) = api.call("GET", "/project", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(p["document_prompt"], "");

    api.store
        .apply(
            Origin::User,
            Command::UpdateProject {
                title: None,
                document_prompt: Some("Write in plain English.".into()),
                code_guidance: Some("Prefer small functions.".into()),
            },
            None,
        )
        .unwrap();
    let (_, p) = api.call("GET", "/project", None).await;
    assert_eq!(p["document_prompt"], "Write in plain English.");
    assert_eq!(p["code_guidance"], "Prefer small functions.");

    // There is no way to write it over the API.
    let (status, _) = api
        .call("PUT", "/project", Some(json!({"document_prompt": "x"})))
        .await;
    assert_eq!(status, StatusCode::METHOD_NOT_ALLOWED);
    let (status, _) = api
        .call("PATCH", "/project", Some(json!({"document_prompt": "x"})))
        .await;
    assert_eq!(status, StatusCode::METHOD_NOT_ALLOWED);
    assert_eq!(
        api.store.snapshot().board.project.document_prompt,
        "Write in plain English."
    );
}

#[tokio::test]
async fn tasks_are_numbered_and_addressable_by_number() {
    let api = Api::new(true);
    let mut created = Vec::new();
    for d in ["first", "second"] {
        let (_, t) = api
            .call("POST", "/tasks", Some(json!({"description": d})))
            .await;
        created.push(t);
    }
    assert_eq!(created[0]["number"], 1);
    assert_eq!(created[1]["number"], 2);

    // "#2", "2" and the id all find the same task.
    for reference in ["%232", "2", created[1]["id"].as_str().unwrap()] {
        let (status, t) = api.call("GET", &format!("/tasks/{reference}"), None).await;
        assert_eq!(status, StatusCode::OK, "{reference}");
        assert_eq!(t["description"], "second");
    }
    let (status, err) = api.call("GET", "/tasks/%2399", None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert!(err["message"].as_str().unwrap().contains("#99"));
    let (status, err) = api.call("GET", "/tasks/banana", None).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(err["message"].as_str().unwrap().contains("#12"));

    // Numbers work in writes and references, and show up in summaries.
    let (status, t) = api
        .call(
            "PATCH",
            "/tasks/%231",
            Some(json!({"references": [{"task_id": "#2", "relation": "blocks"}]})),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(t["references"][0]["number"], 2);
    let (status, _) = api.call("POST", "/tasks/%232/advance", None).await;
    assert_eq!(status, StatusCode::OK);
    let (_, list) = api.call("GET", "/tasks", None).await;
    assert_eq!(list[0]["number"], 1);

    // Deleting #2 retires its number.
    api.call("DELETE", "/tasks/%232", None).await;
    let (_, t) = api
        .call("POST", "/tasks", Some(json!({"description": "third"})))
        .await;
    assert_eq!(t["number"], 3);
}

#[tokio::test]
async fn validation_errors() {
    let api = Api::new(true);
    let (status, _) = api
        .call("POST", "/tasks", Some(json!({"description": "  "})))
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = api.call("GET", "/tasks/not-a-uuid", None).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, err) = api.call("GET", "/tasks?column=nope", None).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(err["message"].as_str().unwrap().contains("Backlog"));
}

#[tokio::test]
async fn patching_a_criterion_with_a_malformed_id_is_a_bad_request() {
    let api = Api::new(true);
    let (_, t) = api
        .call("POST", "/tasks", Some(json!({"description": "t"})))
        .await;
    let id = t["id"].as_str().unwrap();
    let (status, err) = api
        .call(
            "PATCH",
            &format!("/tasks/{id}"),
            Some(json!({"acceptance_criteria": [{"id": "nope", "text": "x"}]})),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(
        err,
        json!({"error": "bad_request", "message": "'nope' is not a valid criterion id"})
    );
}

#[tokio::test]
async fn mcp_end_to_end() {
    let store = BoardStore::new(true);
    let handle = stickynotes_server::start(store.clone(), TOKEN.into(), 0)
        .await
        .unwrap();

    let config =
        StreamableHttpClientTransportConfig::with_uri(format!("http://{}/mcp", handle.addr))
            .auth_header(TOKEN);
    let client = ().serve(StreamableHttpClientTransport::from_config(config)).await.unwrap();

    let info = client.peer_info().unwrap();
    assert!(
        info.instructions
            .as_deref()
            .unwrap()
            .contains("task_advance")
    );

    let tools = client.list_all_tools().await.unwrap();
    let mut names: Vec<_> = tools.iter().map(|t| t.name.to_string()).collect();
    names.sort();
    // The tool list in the instructions and skill must match what is served.
    let mut documented: Vec<_> = agent_guide::TOOLS
        .iter()
        .map(|(n, _)| n.to_string())
        .collect();
    documented.sort();
    assert_eq!(names, documented);
    assert!(names.contains(&"project_get".to_string()));

    store
        .apply(
            Origin::User,
            Command::UpdateProject {
                title: None,
                document_prompt: Some("Be brief.".into()),
                code_guidance: None,
            },
            None,
        )
        .unwrap();
    let result = client
        .call_tool(CallToolRequestParams::new("project_get"))
        .await
        .unwrap();
    assert_ne!(result.is_error, Some(true));
    let project: Value = serde_json::from_str(&result.content[0].as_text().unwrap().text).unwrap();
    assert_eq!(project["document_prompt"], "Be brief.");

    let args = json!({"description": "From MCP"})
        .as_object()
        .unwrap()
        .clone();
    let result = client
        .call_tool(CallToolRequestParams::new("task_create").with_arguments(args))
        .await
        .unwrap();
    assert_ne!(result.is_error, Some(true));
    let text = result.content[0].as_text().unwrap().text.clone();
    let task: Value = serde_json::from_str(&text).unwrap();
    let id = task["id"].as_str().unwrap().to_string();

    let args = json!({"id": id}).as_object().unwrap().clone();
    let result = client
        .call_tool(CallToolRequestParams::new("task_advance").with_arguments(args))
        .await
        .unwrap();
    assert_ne!(result.is_error, Some(true));
    assert_eq!(
        store.read(|b, _| b.locate_task(id.parse().unwrap())),
        Some((1, 0))
    );

    // Link two tasks over MCP; the other side sees the mirrored relation.
    let args = json!({"description": "Second"})
        .as_object()
        .unwrap()
        .clone();
    let result = client
        .call_tool(CallToolRequestParams::new("task_create").with_arguments(args))
        .await
        .unwrap();
    let second: Value = serde_json::from_str(&result.content[0].as_text().unwrap().text).unwrap();
    let second_id = second["id"].as_str().unwrap().to_string();
    let args = json!({"id": id, "references": [{"task_id": second_id, "relation": "relates_to"}]})
        .as_object()
        .unwrap()
        .clone();
    let result = client
        .call_tool(CallToolRequestParams::new("task_update").with_arguments(args))
        .await
        .unwrap();
    assert_ne!(result.is_error, Some(true));
    let other = store
        .read(|b, _| b.task(second_id.parse().unwrap()).cloned())
        .unwrap();
    assert_eq!(other.references.len(), 1);

    // Categories over MCP: create with one, then set the other with different case.
    let args = json!({"description": "Cat A", "category": "UI"})
        .as_object()
        .unwrap()
        .clone();
    let result = client
        .call_tool(CallToolRequestParams::new("task_create").with_arguments(args))
        .await
        .unwrap();
    assert_ne!(result.is_error, Some(true));
    let args = json!({"id": second_id, "category": "ui"})
        .as_object()
        .unwrap()
        .clone();
    let result = client
        .call_tool(CallToolRequestParams::new("task_update").with_arguments(args))
        .await
        .unwrap();
    assert_ne!(result.is_error, Some(true));
    let updated: Value = serde_json::from_str(&result.content[0].as_text().unwrap().text).unwrap();
    assert_eq!(updated["category"], "UI");
    let schema = tools
        .iter()
        .find(|t| t.name == "task_update")
        .map(|t| serde_json::to_string(&t.input_schema).unwrap())
        .unwrap();
    assert!(schema.contains("category"));

    store.set_agent_write(false);
    let args = json!({"id": id}).as_object().unwrap().clone();
    let result = client
        .call_tool(CallToolRequestParams::new("task_delete").with_arguments(args))
        .await
        .unwrap();
    assert_eq!(result.is_error, Some(true));

    let resource = client
        .read_resource(ReadResourceRequestParams::new("stickynotes://board.md"))
        .await
        .unwrap();
    assert!(format!("{:?}", resource.contents).contains("From MCP"));

    client.cancel().await.unwrap();
    handle.shutdown();
}

/// A PNG header followed by `len` bytes, base64 encoded.
fn png_base64(len: usize) -> String {
    use base64::Engine as _;
    let mut bytes = b"\x89PNG\r\n\x1a\n".to_vec();
    bytes.resize(len, 7);
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

#[tokio::test]
async fn artifacts_are_attached_read_and_detached() {
    let (_root, api) = Api::in_project();
    let (_, task) = api
        .call("POST", "/tasks", Some(json!({"description": "T"})))
        .await;
    let id = task["id"].as_str().unwrap();

    let (status, added) = api
        .call(
            "POST",
            &format!("/tasks/{id}/artifacts"),
            Some(json!({"name": "Design Notes.md", "content": "# Design"})),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{added}");
    assert_eq!(added["artifact"]["name"], "Design-Notes.md");
    assert_eq!(added["artifact"]["kind"], "markdown");
    assert_eq!(added["artifact"]["path"], "artifacts/Design-Notes.md");
    assert_eq!(added["artifact"]["added_by_agent"], true);
    // REST has no client name; the stage is the column the task was in.
    assert_eq!(added["artifact"]["added_by"], "agent");
    assert_eq!(added["artifact"]["stage"], task["column"]["title"]);
    assert!(added["artifact"]["added_at"].is_string());

    let (status, _) = api
        .call(
            "POST",
            "/tasks/%231/artifacts",
            Some(json!({"name": "shot.png", "content_base64": png_base64(64)})),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "task is addressable as #1");

    let (_, task) = api.call("GET", &format!("/tasks/{id}"), None).await;
    let names: Vec<_> = task["artifacts"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| a["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["Design-Notes.md", "shot.png"]);

    // Text comes back by file name; images are metadata only.
    let (_, md) = api
        .call(
            "GET",
            &format!("/tasks/{id}/artifacts/Design-Notes.md"),
            None,
        )
        .await;
    assert_eq!(md["content"], "# Design");
    let (_, img) = api
        .call("GET", &format!("/tasks/{id}/artifacts/shot.png"), None)
        .await;
    assert_eq!(img["content"], Value::Null);
    assert_eq!(img["kind"], "image");

    // Detach by id: the record goes, the file stays.
    let aid = added["artifact"]["id"].as_str().unwrap();
    let (status, task) = api
        .call("DELETE", &format!("/tasks/{id}/artifacts/{aid}"), None)
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(task["artifacts"].as_array().unwrap().len(), 1);
    assert_eq!(api.store.artifact_files().len(), 2);
    let (status, _) = api
        .call("GET", &format!("/tasks/{id}/artifacts/{aid}"), None)
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn artifact_requests_are_validated() {
    let (_root, api) = Api::in_project();
    let (_, task) = api
        .call("POST", "/tasks", Some(json!({"description": "T"})))
        .await;
    let uri = format!("/tasks/{}/artifacts", task["id"].as_str().unwrap());
    for body in [
        json!({"name": "run.sh", "content": "echo hi"}),
        json!({"name": "no-extension", "content": "x"}),
        json!({"name": "a.png", "content": "text, not a png"}),
        json!({"name": "a.png", "content_base64": "!!! not base64"}),
        json!({"name": "a.md"}),
        json!({"name": "a.md", "content": "x", "content_base64": "eA=="}),
        json!({"name": "a.md", "content": ""}),
    ] {
        let (status, err) = api.call("POST", &uri, Some(body.clone())).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{body}: {err}");
    }
    assert!(api.store.artifact_files().is_empty());

    api.store.set_agent_write(false);
    let (status, _) = api
        .call("POST", &uri, Some(json!({"name": "a.md", "content": "x"})))
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Without a project there is nowhere to put the file.
    let loose = Api::new(true);
    let (_, task) = loose
        .call("POST", "/tasks", Some(json!({"description": "T"})))
        .await;
    let (status, err) = loose
        .call(
            "POST",
            &format!("/tasks/{}/artifacts", task["id"].as_str().unwrap()),
            Some(json!({"name": "a.md", "content": "x"})),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "{err}");
    assert_eq!(err["error"], "no_project");
}

#[tokio::test]
async fn a_large_image_can_be_attached_over_mcp() {
    let (_root, api) = Api::in_project();
    let handle = stickynotes_server::start(api.store.clone(), TOKEN.into(), 0)
        .await
        .unwrap();
    let config =
        StreamableHttpClientTransportConfig::with_uri(format!("http://{}/mcp", handle.addr))
            .auth_header(TOKEN);
    let client = ().serve(StreamableHttpClientTransport::from_config(config)).await.unwrap();

    let result = client
        .call_tool(
            CallToolRequestParams::new("task_create")
                .with_arguments(json!({"description": "T"}).as_object().unwrap().clone()),
        )
        .await
        .unwrap();
    let task: Value = serde_json::from_str(&result.content[0].as_text().unwrap().text).unwrap();
    let id = task["id"].as_str().unwrap();

    // Just under the 5 MiB limit, so the encoded request is about 6.7 MB.
    let big = 5 * 1024 * 1024 - 16;
    let args = json!({"task_id": id, "name": "big.png", "content_base64": png_base64(big)});
    let result = client
        .call_tool(
            CallToolRequestParams::new("artifact_add")
                .with_arguments(args.as_object().unwrap().clone()),
        )
        .await
        .unwrap();
    assert_ne!(result.is_error, Some(true), "{:?}", result.content);
    assert_eq!(api.store.read_artifact("big.png").unwrap().len(), big);
    // The MCP client's name from its initialize info is recorded.
    let added: Value = serde_json::from_str(&result.content[0].as_text().unwrap().text).unwrap();
    assert!(added["artifact"]["added_by"].is_string());
    assert_ne!(added["artifact"]["added_by"], "user");

    let args = json!({"task_id": id, "artifact": "big.png"});
    let result = client
        .call_tool(
            CallToolRequestParams::new("artifact_detach")
                .with_arguments(args.as_object().unwrap().clone()),
        )
        .await
        .unwrap();
    assert_ne!(result.is_error, Some(true));

    client.cancel().await.unwrap();
    handle.shutdown();
}

#[tokio::test]
async fn the_activity_log_names_the_mcp_client_and_rest_is_agent() {
    let (root, api) = Api::in_project();
    let handle = stickynotes_server::start(api.store.clone(), TOKEN.into(), 0)
        .await
        .unwrap();
    let config =
        StreamableHttpClientTransportConfig::with_uri(format!("http://{}/mcp", handle.addr))
            .auth_header(TOKEN);
    let client = ().serve(StreamableHttpClientTransport::from_config(config)).await.unwrap();
    client
        .call_tool(
            CallToolRequestParams::new("task_create").with_arguments(
                json!({"description": "Via MCP"})
                    .as_object()
                    .unwrap()
                    .clone(),
            ),
        )
        .await
        .unwrap();
    client.cancel().await.unwrap();
    handle.shutdown();
    api.call("POST", "/tasks", Some(json!({"description": "Via REST"})))
        .await;

    let entries = stickynotes_core::activity::read(&root.path().join("p"));
    assert_eq!(entries.len(), 2);
    assert_eq!(entries[0].title, "Via MCP");
    assert_ne!(entries[0].agent, "agent");
    assert!(!entries[0].agent.is_empty());
    assert_eq!(
        (entries[1].title.as_str(), entries[1].agent.as_str()),
        ("Via REST", "agent")
    );
}
