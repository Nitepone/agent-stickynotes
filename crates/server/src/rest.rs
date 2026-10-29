//! REST transport: `/api/v1/...`.

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post, put};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::json;
use stickynotes_core::Error;

use crate::service::{AgentService, NewTask, ServiceError, TaskUpdate};

pub fn router(service: AgentService) -> Router {
    Router::new()
        .route("/board", get(board))
        .route("/export/markdown", get(markdown))
        .route("/tasks", get(list_tasks).post(create_task))
        .route(
            "/tasks/{id}",
            get(get_task).patch(update_task).delete(delete_task),
        )
        .route("/tasks/{id}/advance", post(advance_task))
        .route("/tasks/{id}/criteria/{cid}", put(set_criterion))
        .with_state(service)
}

type ApiResult = Result<Response, ServiceError>;

async fn board(State(s): State<AgentService>) -> Json<crate::service::BoardView> {
    Json(s.board())
}

async fn markdown(State(s): State<AgentService>) -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/markdown; charset=utf-8")],
        s.markdown(),
    )
}

#[derive(Deserialize)]
struct ListQuery {
    column: Option<String>,
}

async fn list_tasks(State(s): State<AgentService>, Query(q): Query<ListQuery>) -> ApiResult {
    Ok(Json(s.list_tasks(q.column.as_deref())?).into_response())
}

async fn get_task(State(s): State<AgentService>, Path(id): Path<String>) -> ApiResult {
    Ok(Json(s.task(&id)?).into_response())
}

async fn create_task(
    State(s): State<AgentService>,
    headers: HeaderMap,
    Json(body): Json<NewTask>,
) -> ApiResult {
    let view = s.create_task(body, if_match(&headers)?)?;
    Ok((StatusCode::CREATED, Json(view)).into_response())
}

async fn update_task(
    State(s): State<AgentService>,
    Path(id): Path<String>,
    headers: HeaderMap,
    Json(body): Json<TaskUpdate>,
) -> ApiResult {
    Ok(Json(s.update_task(&id, body, if_match(&headers)?)?).into_response())
}

async fn advance_task(
    State(s): State<AgentService>,
    Path(id): Path<String>,
    headers: HeaderMap,
) -> ApiResult {
    Ok(Json(s.advance_task(&id, if_match(&headers)?)?).into_response())
}

#[derive(Deserialize)]
struct CriterionBody {
    done: bool,
}

async fn set_criterion(
    State(s): State<AgentService>,
    Path((id, cid)): Path<(String, String)>,
    headers: HeaderMap,
    Json(body): Json<CriterionBody>,
) -> ApiResult {
    Ok(Json(s.set_criterion(&id, &cid, body.done, if_match(&headers)?)?).into_response())
}

async fn delete_task(
    State(s): State<AgentService>,
    Path(id): Path<String>,
    headers: HeaderMap,
) -> ApiResult {
    Ok(Json(s.delete_task(&id, if_match(&headers)?)?).into_response())
}

/// `If-Match: <revision>` (quotes optional) for optimistic concurrency.
fn if_match(headers: &HeaderMap) -> Result<Option<u64>, ServiceError> {
    headers
        .get(header::IF_MATCH)
        .map(|v| {
            v.to_str()
                .ok()
                .and_then(|s| s.trim().trim_matches('"').parse().ok())
                .ok_or_else(|| {
                    ServiceError::BadRequest("If-Match must be a revision number".into())
                })
        })
        .transpose()
}

impl IntoResponse for ServiceError {
    fn into_response(self) -> Response {
        let (status, code) = match &self {
            ServiceError::BadRequest(_) => (StatusCode::BAD_REQUEST, "bad_request"),
            ServiceError::Core(e) => match e {
                Error::NotFound { .. } => (StatusCode::NOT_FOUND, "not_found"),
                Error::Validation(_) => (StatusCode::BAD_REQUEST, "validation"),
                Error::AgentWriteDisabled => (StatusCode::FORBIDDEN, "agent_write_disabled"),
                Error::AgentNotPermitted(_) => (StatusCode::FORBIDDEN, "not_permitted"),
                Error::RevisionConflict { .. } => (StatusCode::CONFLICT, "revision_conflict"),
                _ => (StatusCode::INTERNAL_SERVER_ERROR, "internal"),
            },
        };
        let body = json!({ "error": code, "message": self.to_string() });
        (status, Json(body)).into_response()
    }
}
