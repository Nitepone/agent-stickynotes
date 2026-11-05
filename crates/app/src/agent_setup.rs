//! What the **Connect Agent** dialog shows: the setup text for each client and
//! a check that the app's own agent endpoint answers.
//!
//! The Claude Code CLI command lives in `context.rs` and must not change, or
//! existing registrations (same URL, server name, header) stop matching.

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::time::Duration;

use serde_json::{Value, json};

/// Server name used by every client; the same name the CLI registers.
pub const SERVER_NAME: &str = "stickynotes";

/// A `.mcp.json` entry (Claude Code project scope). The Claude Code Desktop
/// Code tab reads it without the `claude` CLI being installed.
pub fn claude_desktop_project_json(endpoint: &str, token: &str) -> String {
    pretty(json!({
        "mcpServers": {
            SERVER_NAME: {
                "type": "http",
                "url": format!("{endpoint}/mcp"),
                "headers": { "Authorization": format!("Bearer {token}") }
            }
        }
    }))
}

/// A `claude_desktop_config.json` entry. That file only starts local (stdio)
/// servers, so `mcp-remote` (run with npx, needs Node.js) bridges to HTTP.
pub fn claude_desktop_bridge_json(endpoint: &str, token: &str) -> String {
    pretty(json!({
        "mcpServers": {
            SERVER_NAME: {
                "command": "npx",
                "args": [
                    "-y", "mcp-remote", format!("{endpoint}/mcp"),
                    "--allow-http",
                    "--header", "Authorization:${AUTH_HEADER}"
                ],
                "env": { "AUTH_HEADER": format!("Bearer {token}") }
            }
        }
    }))
}

/// An `opencode.json` entry.
pub fn opencode_json(endpoint: &str, token: &str) -> String {
    pretty(json!({
        "$schema": "https://opencode.ai/config.json",
        "mcp": {
            SERVER_NAME: {
                "type": "remote",
                "url": format!("{endpoint}/mcp"),
                "enabled": true,
                "headers": { "Authorization": format!("Bearer {token}") }
            }
        }
    }))
}

fn pretty(value: Value) -> String {
    serde_json::to_string_pretty(&value).expect("setup JSON serializes")
}

/// Ask the app's own server for the project with the bearer token. This shows
/// that the endpoint is up and the token is accepted; it says nothing about an
/// external client's configuration.
/// The port of an endpoint such as `http://127.0.0.1:7317`; 0 if it has none.
pub fn port_of(endpoint: &str) -> u16 {
    endpoint
        .rsplit_once(':')
        .and_then(|(_, port)| port.trim_end_matches('/').parse().ok())
        .unwrap_or(0)
}

pub fn check_endpoint(endpoint: &str, token: &str) -> Result<(), String> {
    let host = endpoint
        .strip_prefix("http://")
        .ok_or("the agent endpoint is not a plain http address")?;
    let addr: SocketAddr = host
        .to_socket_addrs()
        .ok()
        .and_then(|mut a| a.next())
        .ok_or("the agent endpoint address is not valid")?;
    let timeout = Duration::from_secs(3);
    let mut stream = TcpStream::connect_timeout(&addr, timeout)
        .map_err(|e| format!("Could not reach the agent endpoint {endpoint}: {e}"))?;
    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));
    let request = format!(
        "GET /api/v1/project HTTP/1.1\r\nHost: {host}\r\nAuthorization: Bearer {token}\r\nConnection: close\r\n\r\n"
    );
    stream
        .write_all(request.as_bytes())
        .map_err(|e| format!("Could not send the request: {e}"))?;
    let mut head = Vec::new();
    // Only the status line is needed.
    let _ = stream.take(256).read_to_end(&mut head);
    let head = String::from_utf8_lossy(&head);
    let status = head
        .lines()
        .next()
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|s| s.parse::<u16>().ok());
    match status {
        // 409 (no project open) still means the token was accepted.
        Some(200..=299 | 409) => Ok(()),
        Some(401) => Err("The agent endpoint rejected the token (401).".into()),
        Some(code) => Err(format!("The agent endpoint answered with status {code}.")),
        None => Err("The agent endpoint gave no valid HTTP answer.".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::context::command_for;
    use stickynotes_core::BoardStore;

    const EP: &str = "http://127.0.0.1:7317";

    #[test]
    fn the_port_comes_from_the_endpoint() {
        assert_eq!(port_of("http://127.0.0.1:7317"), 7317);
        assert_eq!(port_of("http://127.0.0.1:40123/"), 40123);
        assert_eq!(port_of("http://localhost"), 0);
    }

    #[test]
    fn cli_command_text_is_unchanged() {
        // Existing registrations depend on this exact text.
        assert_eq!(
            command_for(EP, "TOKEN"),
            "claude mcp add --transport http --scope user stickynotes http://127.0.0.1:7317/mcp --header \"Authorization: Bearer TOKEN\""
        );
    }

    fn parse(s: &str) -> Value {
        serde_json::from_str(s).expect("valid JSON")
    }

    #[test]
    fn project_snippet_has_endpoint_and_header() {
        let v = parse(&claude_desktop_project_json(EP, "TOKEN"));
        let s = &v["mcpServers"]["stickynotes"];
        assert_eq!(s["type"], "http");
        assert_eq!(s["url"], "http://127.0.0.1:7317/mcp");
        assert_eq!(s["headers"]["Authorization"], "Bearer TOKEN");
    }

    #[test]
    fn bridge_snippet_runs_mcp_remote_with_the_token() {
        let v = parse(&claude_desktop_bridge_json(EP, "TOKEN"));
        let s = &v["mcpServers"]["stickynotes"];
        assert_eq!(s["command"], "npx");
        let args: Vec<&str> = s["args"]
            .as_array()
            .unwrap()
            .iter()
            .map(|a| a.as_str().unwrap())
            .collect();
        assert!(args.contains(&"http://127.0.0.1:7317/mcp"));
        assert!(args.contains(&"Authorization:${AUTH_HEADER}"));
        assert_eq!(s["env"]["AUTH_HEADER"], "Bearer TOKEN");
    }

    #[test]
    fn opencode_snippet_is_a_remote_entry() {
        let v = parse(&opencode_json(EP, "TOKEN"));
        let s = &v["mcp"]["stickynotes"];
        assert_eq!(s["type"], "remote");
        assert_eq!(s["url"], "http://127.0.0.1:7317/mcp");
        assert_eq!(s["headers"]["Authorization"], "Bearer TOKEN");
    }

    #[test]
    fn check_against_the_real_server() {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .enable_all()
            .build()
            .unwrap();
        let server = runtime
            .block_on(stickynotes_server::start(
                BoardStore::new(false),
                "good".into(),
                0,
            ))
            .unwrap();
        let endpoint = format!("http://{}", server.addr);
        assert_eq!(check_endpoint(&endpoint, "good"), Ok(()));
        let err = check_endpoint(&endpoint, "bad").unwrap_err();
        assert!(err.contains("401"), "{err}");
        server.shutdown();

        // Nothing listens on a port that was just released.
        let port = std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let err = check_endpoint(&format!("http://127.0.0.1:{port}"), "good").unwrap_err();
        assert!(err.contains("Could not reach"), "{err}");
    }
}
