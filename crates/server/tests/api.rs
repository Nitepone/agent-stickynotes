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
