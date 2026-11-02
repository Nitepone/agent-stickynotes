//! Drafts by asking an Ollama-style server over HTTP.
//!
//! Ollama and llama.cpp's `llama-server` (and most other local servers) both
//! answer the OpenAI-compatible `POST {endpoint}/v1/chat/completions`, so that
//! one protocol is used for all of them. The request is not streamed and asks
//! for a JSON reply; `Authorization: Bearer <token>` is sent only when a token
//! is configured. The token is never logged or put into an error message.
//!
//! The request runs on its own thread so cancelling does not have to wait for
//! the network: the abandoned request ends by itself at the timeout.

use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use super::{CancelToken, Draft, DraftBackend, DraftError, DraftRequest, parse_reply};

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(180);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const POLL: Duration = Duration::from_millis(40);
/// The whole "Test connection" check, connect included.
const CHECK_TIMEOUT: Duration = Duration::from_secs(15);

const REJECTED_TOKEN: &str =
    "The server rejected the auth token. Check the token in Preferences > Editor.";

/// The one HTTP client setup, shared by drafting and the connection check.
fn http_agent(timeout: Duration) -> ureq::Agent {
    ureq::Agent::config_builder()
        .http_status_as_error(false)
        .timeout_connect(Some(CONNECT_TIMEOUT))
        .timeout_global(Some(timeout))
        .build()
        .into()
}

fn unreachable_message(endpoint: &str) -> String {
    format!(
        "Cannot reach the Ollama server at {endpoint}. Check that it is running and that the \
endpoint in Preferences > Editor is right."
    )
}

fn status_message(endpoint: &str, status: u16, body: &str) -> String {
    format!(
        "The Ollama server at {endpoint} answered with status {status}. {}",
        excerpt(body)
    )
}

/// A successful connection check; `note` is a gentle remark, not an error.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConnectionOk {
    pub note: Option<String>,
}

/// Ask the server's model list (`GET {endpoint}/v1/models`) to find out
/// whether drafting can work, without drafting anything. A model that is not
/// in the list, or a list that cannot be read, is only a note: the server
/// answered. Errors use drafting's wording and never contain the token.
pub fn check_connection(endpoint: &str, token: &str, model: &str) -> Result<ConnectionOk, String> {
    check_connection_within(endpoint, token, model, CHECK_TIMEOUT)
}

fn check_connection_within(
    endpoint: &str,
    token: &str,
    model: &str,
    timeout: Duration,
) -> Result<ConnectionOk, String> {
    let endpoint = endpoint.trim_end_matches('/');
    let timed_out = || {
        format!(
            "The Ollama server at {endpoint} did not answer within {} seconds.",
            timeout.as_secs().max(1)
        )
    };
    let mut call = http_agent(timeout).get(format!("{endpoint}/v1/models"));
    if !token.is_empty() {
        call = call.header("Authorization", format!("Bearer {token}"));
    }
    let mut response = call.call().map_err(|e| match e {
        ureq::Error::Timeout(
            ureq::Timeout::Global | ureq::Timeout::RecvResponse | ureq::Timeout::RecvBody,
        ) => timed_out(),
        _ => unreachable_message(endpoint),
    })?;
    let status = response.status().as_u16();
    let text = response.body_mut().read_to_string().map_err(|e| match e {
        ureq::Error::Timeout(_) => timed_out(),
        _ => format!("The Ollama server at {endpoint} sent an unreadable reply."),
    })?;
    match status {
        200..=299 => {
            let model = model.trim();
            let listed = listed_models(&text);
            let note = (!model.is_empty() && !listed.is_some_and(|l| has_model(&l, model)))
                .then(|| format!("Connected. Model '{model}' was not listed by the server."));
            Ok(ConnectionOk { note })
        }
        401 | 403 => Err(REJECTED_TOKEN.into()),
        _ => Err(status_message(endpoint, status, &text)),
    }
}

/// Model names in an OpenAI-style (`data[].id`) or Ollama-style
/// (`models[].name`) list; `None` when the body is neither.
fn listed_models(body: &str) -> Option<Vec<String>> {
    let value: serde_json::Value = serde_json::from_str(body).ok()?;
    let mut names = Vec::new();
    let mut found = false;
    for (list, keys) in [("data", &["id"][..]), ("models", &["name", "model"][..])] {
        if let Some(items) = value[list].as_array() {
            found = true;
            for item in items {
                names.extend(
                    keys.iter()
                        .filter_map(|k| item[*k].as_str())
                        .map(String::from),
                );
            }
        }
    }
    found.then_some(names)
}

/// Servers list `llama3.2:latest` for a model configured as `llama3.2`.
fn has_model(listed: &[String], model: &str) -> bool {
    listed
        .iter()
        .any(|n| n == model || n.strip_suffix(":latest") == Some(model))
}

pub struct OllamaBackend {
    endpoint: String,
    token: String,
    timeout: Duration,
}

// Hand written so the token cannot appear in debug output.
impl std::fmt::Debug for OllamaBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OllamaBackend")
            .field("endpoint", &self.endpoint)
            .field(
                "token",
                &if self.token.is_empty() {
                    "unset"
                } else {
                    "<hidden>"
                },
            )
            .finish()
    }
}

impl OllamaBackend {
    /// `endpoint` is the server's base URL (no trailing slash); an empty
    /// `token` means the server needs none.
    pub fn new(endpoint: impl Into<String>, token: impl Into<String>) -> Self {
        OllamaBackend {
            endpoint: endpoint.into().trim_end_matches('/').to_string(),
            token: token.into(),
            timeout: DEFAULT_TIMEOUT,
        }
    }

    #[cfg(test)]
    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    fn url(&self) -> String {
        format!("{}/v1/chat/completions", self.endpoint)
    }

    fn unreachable(&self) -> DraftError {
        DraftError::Unavailable(unreachable_message(&self.endpoint))
    }

    fn body(request: &DraftRequest) -> String {
        serde_json::json!({
            "model": request.options.model,
            "stream": false,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": request.system_prompt()},
                {"role": "user", "content": request.ticket_json()},
            ],
        })
        .to_string()
    }

    /// The blocking HTTP exchange. Returns the model's reply text.
    fn post(&self, body: String) -> Result<String, DraftError> {
        let mut call = http_agent(self.timeout)
            .post(self.url())
            .header("Content-Type", "application/json");
        if !self.token.is_empty() {
            call = call.header("Authorization", format!("Bearer {}", self.token));
        }
        let mut response = call.send(body).map_err(|e| match e {
            ureq::Error::Timeout(
                ureq::Timeout::Global | ureq::Timeout::RecvResponse | ureq::Timeout::RecvBody,
            ) => DraftError::TimedOut(self.timeout.as_secs()),
            _ => self.unreachable(),
        })?;
        let status = response.status().as_u16();
        let text = response.body_mut().read_to_string().map_err(|e| match e {
            ureq::Error::Timeout(_) => DraftError::TimedOut(self.timeout.as_secs()),
            e => DraftError::Failed(format!(
                "The Ollama server at {} sent an unreadable reply: {e}",
                self.endpoint
            )),
        })?;
        match status {
            200..=299 => reply_text(&text),
            401 | 403 => Err(DraftError::Failed(REJECTED_TOKEN.into())),
            _ => Err(DraftError::Failed(status_message(
                &self.endpoint,
                status,
                &text,
            ))),
        }
    }
}

impl DraftBackend for OllamaBackend {
    fn name(&self) -> &str {
        "Ollama"
    }

    fn generate(&self, request: &DraftRequest, cancel: &CancelToken) -> Result<Draft, DraftError> {
        if request.options.model.trim().is_empty() {
            return Err(DraftError::Unavailable(
                "No model is set. Enter the model name to use (for example llama3.2) in \
Preferences > Editor."
                    .into(),
            ));
        }
        if cancel.is_cancelled() {
            return Err(DraftError::Cancelled);
        }
        let (tx, rx) = mpsc::channel();
        let worker = OllamaBackend {
            endpoint: self.endpoint.clone(),
            token: self.token.clone(),
            timeout: self.timeout,
        };
        let body = Self::body(request);
        thread::spawn(move || {
            let _ = tx.send(worker.post(body));
        });
        loop {
            match rx.recv_timeout(POLL) {
                Ok(result) => return parse_reply(&result?),
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if cancel.is_cancelled() {
                        return Err(DraftError::Cancelled);
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    return Err(DraftError::Failed(
                        "The request stopped unexpectedly.".into(),
                    ));
                }
            }
        }
    }
}

/// The assistant's text from an OpenAI-style chat completion.
fn reply_text(body: &str) -> Result<String, DraftError> {
    let value: serde_json::Value = serde_json::from_str(body).map_err(|_| {
        DraftError::BadReply(format!(
            "The server did not answer in the OpenAI chat format. It began: {}",
            excerpt(body)
        ))
    })?;
    value["choices"][0]["message"]["content"]
        .as_str()
        .map(String::from)
        .ok_or_else(|| {
            DraftError::BadReply(format!(
                "The server's answer had no message. It began: {}",
                excerpt(body)
            ))
        })
}

fn excerpt(text: &str) -> String {
    let text: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let short: String = text.chars().take(200).collect();
    if text.chars().count() > 200 {
        format!("{short}...")
    } else {
        short
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::drafting::DraftOptions;
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::{Arc, Mutex};
    use std::time::Instant;

    /// A one-route HTTP server: answers every request with `status` and
    /// `body`, and keeps the raw requests it saw.
    struct Mock {
        url: String,
        seen: Arc<Mutex<Vec<String>>>,
    }

    fn mock(status: u16, body: &str, delay: Duration) -> Mock {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let seen = Arc::new(Mutex::new(Vec::new()));
        let log = seen.clone();
        let body = body.to_string();
        thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { return };
                let mut raw = Vec::new();
                let mut buf = [0u8; 4096];
                loop {
                    let n = stream.read(&mut buf).unwrap_or(0);
                    raw.extend_from_slice(&buf[..n]);
                    let text = String::from_utf8_lossy(&raw).into_owned();
                    if let Some(split) = text.find("\r\n\r\n") {
                        let len = text[..split]
                            .lines()
                            .find_map(|l| {
                                l.to_ascii_lowercase()
                                    .strip_prefix("content-length:")
                                    .map(|v| v.trim().parse::<usize>().unwrap_or(0))
                            })
                            .unwrap_or(0);
                        if raw.len() >= split + 4 + len {
                            break;
                        }
                    }
                    if n == 0 {
                        break;
                    }
                }
                log.lock()
                    .unwrap()
                    .push(String::from_utf8_lossy(&raw).into_owned());
                thread::sleep(delay);
                let _ = write!(
                    stream,
                    "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
            }
        });
        Mock { url, seen }
    }

    fn completion(content: &str) -> String {
        serde_json::json!({"choices": [{"message": {"role": "assistant", "content": content}}]})
            .to_string()
    }

    fn request(model: &str) -> DraftRequest {
        DraftRequest {
            description: "Add a login page".into(),
            requirements: vec!["Use HTTPS".into()],
            options: DraftOptions {
                model: model.into(),
                ..DraftOptions::default()
            },
            ..DraftRequest::default()
        }
    }

    const REPLY: &str = r#"{"requirements":["Rate limit"],"acceptance_criteria":["Wrong password shows an error"]}"#;

    #[test]
    fn drafts_through_the_chat_completions_endpoint() {
        let server = mock(200, &completion(REPLY), Duration::ZERO);
        let backend = OllamaBackend::new(format!("{}/", server.url), "");
        let draft = backend
            .generate(&request("llama3.2"), &CancelToken::new())
            .unwrap();
        assert_eq!(draft.requirements, ["Rate limit"]);
        assert_eq!(draft.acceptance_criteria, ["Wrong password shows an error"]);

        let seen = server.seen.lock().unwrap();
        let raw = &seen[0];
        assert!(
            raw.starts_with("POST /v1/chat/completions HTTP/1.1"),
            "{raw}"
        );
        let body: serde_json::Value =
            serde_json::from_str(raw.split("\r\n\r\n").nth(1).unwrap()).unwrap();
        assert_eq!(body["model"], "llama3.2");
        assert_eq!(body["stream"], false);
        assert_eq!(body["response_format"]["type"], "json_object");
        assert_eq!(body["messages"][0]["role"], "system");
        assert!(
            body["messages"][0]["content"]
                .as_str()
                .unwrap()
                .contains("ONLY a JSON object")
        );
        assert!(
            body["messages"][1]["content"]
                .as_str()
                .unwrap()
                .contains("Add a login page")
        );
    }

    #[test]
    fn the_bearer_header_is_sent_only_when_a_token_is_set() {
        let server = mock(200, &completion(REPLY), Duration::ZERO);
        OllamaBackend::new(&server.url, "")
            .generate(&request("m"), &CancelToken::new())
            .unwrap();
        OllamaBackend::new(&server.url, "tok-123")
            .generate(&request("m"), &CancelToken::new())
            .unwrap();
        let seen = server.seen.lock().unwrap();
        assert!(!seen[0].to_ascii_lowercase().contains("authorization"));
        assert!(
            seen[1].contains("authorization: Bearer tok-123"),
            "{}",
            seen[1]
        );
    }

    #[test]
    fn a_rejected_token_is_reported_without_echoing_it() {
        for status in [401, 403] {
            let server = mock(status, r#"{"error":"nope tok-123"}"#, Duration::ZERO);
            let err = OllamaBackend::new(&server.url, "tok-123")
                .generate(&request("m"), &CancelToken::new())
                .unwrap_err();
            assert!(err.to_string().contains("rejected the auth token"));
            assert!(!err.to_string().contains("tok-123"), "{err}");
        }
    }

    #[test]
    fn other_errors_show_the_status_and_a_short_excerpt() {
        let server = mock(404, r#"{"error":"model 'm' not found"}"#, Duration::ZERO);
        let err = OllamaBackend::new(&server.url, "")
            .generate(&request("m"), &CancelToken::new())
            .unwrap_err();
        let text = err.to_string();
        assert!(text.contains("404") && text.contains("not found"), "{text}");
    }

    #[test]
    fn an_unreachable_server_is_reported_with_its_endpoint() {
        // A port that was just free and has nothing listening.
        let port = TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let endpoint = format!("http://127.0.0.1:{port}");
        let err = OllamaBackend::new(&endpoint, "tok-123")
            .generate(&request("m"), &CancelToken::new())
            .unwrap_err();
        assert_eq!(err.code(), "unavailable");
        assert!(
            err.to_string()
                .starts_with(&format!("Cannot reach the Ollama server at {endpoint}")),
            "{err}"
        );
        assert!(!err.to_string().contains("tok-123"));
    }

    #[test]
    fn an_empty_model_is_an_error_and_sends_nothing() {
        let server = mock(200, &completion(REPLY), Duration::ZERO);
        let err = OllamaBackend::new(&server.url, "")
            .generate(&request("  "), &CancelToken::new())
            .unwrap_err();
        assert!(err.to_string().contains("No model is set"), "{err}");
        assert!(server.seen.lock().unwrap().is_empty());
    }

    #[test]
    fn malformed_replies_use_the_parse_error_path() {
        let server = mock(200, &completion("I cannot do that."), Duration::ZERO);
        let err = OllamaBackend::new(&server.url, "")
            .generate(&request("m"), &CancelToken::new())
            .unwrap_err();
        assert_eq!(err.code(), "bad_reply");
        let server = mock(200, "<html>not an api</html>", Duration::ZERO);
        let err = OllamaBackend::new(&server.url, "")
            .generate(&request("m"), &CancelToken::new())
            .unwrap_err();
        assert_eq!(err.code(), "bad_reply");
    }

    #[test]
    fn cancelling_stops_waiting_for_a_slow_server() {
        let server = mock(200, &completion(REPLY), Duration::from_secs(5));
        let backend = OllamaBackend::new(&server.url, "");
        let cancel = CancelToken::new();
        let stopper = cancel.clone();
        thread::spawn(move || {
            thread::sleep(Duration::from_millis(150));
            stopper.cancel();
        });
        let started = Instant::now();
        let err = backend.generate(&request("m"), &cancel).unwrap_err();
        assert_eq!(err.code(), "cancelled");
        assert!(started.elapsed() < Duration::from_secs(3));
        // Already cancelled: nothing is sent.
        assert_eq!(
            backend.generate(&request("m"), &cancel).unwrap_err().code(),
            "cancelled"
        );
    }

    #[test]
    fn a_slow_server_times_out() {
        let server = mock(200, &completion(REPLY), Duration::from_secs(5));
        let err = OllamaBackend::new(&server.url, "")
            .with_timeout(Duration::from_millis(300))
            .generate(&request("m"), &CancelToken::new())
            .unwrap_err();
        assert_eq!(err.code(), "timeout");
    }

    fn models(ids: &[&str]) -> String {
        let data: Vec<_> = ids.iter().map(|i| serde_json::json!({"id": i})).collect();
        serde_json::json!({"object": "list", "data": data}).to_string()
    }

    #[test]
    fn a_check_succeeds_when_the_model_is_listed() {
        let server = mock(200, &models(&["llama3.2:latest", "x"]), Duration::ZERO);
        let ok = check_connection(&format!("{}/", server.url), "", "llama3.2").unwrap();
        assert_eq!(ok, ConnectionOk { note: None });
        let seen = server.seen.lock().unwrap();
        assert!(
            seen[0].starts_with("GET /v1/models HTTP/1.1"),
            "{}",
            seen[0]
        );
    }

    #[test]
    fn a_missing_model_or_unreadable_list_is_still_a_success_with_a_note() {
        let note = "Connected. Model 'm' was not listed by the server.";
        for body in [models(&["other"]), "<html>hi</html>".into(), "{}".into()] {
            let server = mock(200, &body, Duration::ZERO);
            let ok = check_connection(&server.url, "", "m").unwrap();
            assert_eq!(ok.note.as_deref(), Some(note), "{body}");
        }
        // Ollama's own list shape.
        let server = mock(200, r#"{"models":[{"name":"m:latest"}]}"#, Duration::ZERO);
        assert_eq!(check_connection(&server.url, "", "m").unwrap().note, None);
        // No model configured: nothing to look for.
        let server = mock(200, &models(&[]), Duration::ZERO);
        assert_eq!(check_connection(&server.url, "", " ").unwrap().note, None);
    }

    #[test]
    fn a_check_reports_a_rejected_token_like_drafting_without_echoing_it() {
        for status in [401, 403] {
            let server = mock(status, r#"{"error":"bad tok-123"}"#, Duration::ZERO);
            let err = check_connection(&server.url, "tok-123", "m").unwrap_err();
            assert_eq!(err, REJECTED_TOKEN);
            let drafting = OllamaBackend::new(&server.url, "tok-123")
                .generate(&request("m"), &CancelToken::new())
                .unwrap_err();
            assert_eq!(err, drafting.to_string());
            assert!(!err.contains("tok-123"));
        }
    }

    #[test]
    fn a_check_of_an_unreachable_server_uses_drafting_wording() {
        let port = TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let endpoint = format!("http://127.0.0.1:{port}");
        let err = check_connection(&endpoint, "tok-123", "m").unwrap_err();
        assert_eq!(err, unreachable_message(&endpoint));
        assert!(err.starts_with(&format!("Cannot reach the Ollama server at {endpoint}")));
        assert!(!err.contains("tok-123"));
    }

    #[test]
    fn a_check_shows_other_statuses_with_an_excerpt() {
        let server = mock(500, r#"{"error":"boom"}"#, Duration::ZERO);
        let err = check_connection(&server.url, "", "m").unwrap_err();
        assert!(err.contains("status 500") && err.contains("boom"), "{err}");
    }

    #[test]
    fn a_check_sends_the_bearer_header_only_with_a_token() {
        let server = mock(200, &models(&["m"]), Duration::ZERO);
        check_connection(&server.url, "", "m").unwrap();
        check_connection(&server.url, "tok-123", "m").unwrap();
        let seen = server.seen.lock().unwrap();
        assert!(!seen[0].to_ascii_lowercase().contains("authorization"));
        assert!(
            seen[1].contains("authorization: Bearer tok-123"),
            "{}",
            seen[1]
        );
    }

    #[test]
    fn a_check_of_a_hung_server_times_out() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        // Accepts and then never answers.
        let _hold = thread::spawn(move || {
            let _conn = listener.accept();
            thread::sleep(Duration::from_secs(5));
        });
        let started = Instant::now();
        let err = check_connection_within(&endpoint, "tok-123", "m", Duration::from_millis(300))
            .unwrap_err();
        assert!(err.contains("did not answer within"), "{err}");
        assert!(!err.contains("tok-123"));
        assert!(started.elapsed() < Duration::from_secs(3));
    }

    #[test]
    fn debug_output_hides_the_token() {
        let backend = OllamaBackend::new("http://h", "tok-123");
        assert!(!format!("{backend:?}").contains("tok-123"));
    }
}
