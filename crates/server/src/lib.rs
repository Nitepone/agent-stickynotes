//! Loopback HTTP server exposing the board to agents: REST under `/api/v1`
//! and MCP (Streamable HTTP) under `/mcp`. Every request needs the bearer
//! token.

pub mod mcp;
pub mod rest;
pub mod service;

use std::net::{Ipv4Addr, SocketAddr};
use std::sync::Arc;

use axum::Router;
use axum::extract::{Request, State};
use axum::http::{StatusCode, header};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use rmcp::transport::streamable_http_server::session::local::LocalSessionManager;
use rmcp::transport::streamable_http_server::{StreamableHttpServerConfig, StreamableHttpService};
use stickynotes_core::BoardStore;
use tokio_util::sync::CancellationToken;

pub use service::AgentService;

pub struct ServerHandle {
    pub addr: SocketAddr,
    cancel: CancellationToken,
}

impl ServerHandle {
    pub fn shutdown(&self) {
        self.cancel.cancel();
    }
}

/// Build the full router (REST + MCP + auth).
pub fn router(store: Arc<BoardStore>, token: String, cancel: CancellationToken) -> Router {
    let service = AgentService::new(store);
    let mcp_service = service.clone();
    let mut config = StreamableHttpServerConfig::default();
    config.cancellation_token = cancel.child_token();
    // Room for the largest artifact once it is base64 encoded.
    config.max_request_body_bytes = rest::ARTIFACT_BODY_LIMIT;
    let mcp: StreamableHttpService<mcp::BoardMcp, LocalSessionManager> = StreamableHttpService::new(
        move || Ok(mcp::BoardMcp::new(mcp_service.clone())),
        Default::default(),
        config,
    );

    Router::new()
        .nest("/api/v1", rest::router(service))
        .nest_service("/mcp", mcp)
        .layer(middleware::from_fn_with_state(
            Arc::new(token),
            require_token,
        ))
}

/// Bind to `127.0.0.1:preferred_port`, falling back to any free port, and
/// serve on the current tokio runtime.
pub async fn start(
    store: Arc<BoardStore>,
    token: String,
    preferred_port: u16,
) -> std::io::Result<ServerHandle> {
    let listener = match tokio::net::TcpListener::bind((Ipv4Addr::LOCALHOST, preferred_port)).await
    {
        Ok(l) => l,
        Err(_) => tokio::net::TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await?,
    };
    let addr = listener.local_addr()?;
    let cancel = CancellationToken::new();
    let app = router(store, token, cancel.clone());
    let shutdown = cancel.clone();
    tokio::spawn(async move {
        let result = axum::serve(listener, app)
            .with_graceful_shutdown(async move { shutdown.cancelled_owned().await })
            .await;
        if let Err(e) = result {
            tracing::error!("agent server stopped: {e}");
        }
    });
    Ok(ServerHandle { addr, cancel })
}

async fn require_token(State(token): State<Arc<String>>, req: Request, next: Next) -> Response {
    let presented = req
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "));
    match presented {
        Some(t) if constant_time_eq(t.as_bytes(), token.as_bytes()) => next.run(req).await,
        _ => (
            StatusCode::UNAUTHORIZED,
            [(header::WWW_AUTHENTICATE, "Bearer")],
            "missing or invalid bearer token",
        )
            .into_response(),
    }
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}
