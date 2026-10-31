//! Drafts by running the Claude Code CLI (`claude -p`) as a subprocess.
//!
//! The system prompt goes in `--system-prompt` and the ticket JSON on stdin.
//! Claude Code is started with no tools, no MCP servers, no slash commands and
//! no session persistence, from a neutral working directory, so it only answers
//! the question and cannot touch the project or the board.

use std::ffi::OsString;
use std::io::{ErrorKind, Read, Write};
use std::process::{Child, Command, Stdio};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use super::{CancelToken, Draft, DraftBackend, DraftError, DraftRequest, parse_reply};

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(180);
const POLL: Duration = Duration::from_millis(40);

pub struct ClaudeCodeBackend {
    command: String,
    timeout: Duration,
}

impl ClaudeCodeBackend {
    /// `command` is the executable to run, normally `claude`.
    pub fn new(command: impl Into<String>) -> Self {
        ClaudeCodeBackend {
            command: command.into(),
            timeout: DEFAULT_TIMEOUT,
        }
    }

    #[cfg(test)]
    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    fn args(request: &DraftRequest) -> Vec<OsString> {
        let mut args: Vec<OsString> = vec![
            "-p".into(),
            "Draft requirements and acceptance criteria for the task given as JSON on stdin."
                .into(),
            "--output-format".into(),
            "text".into(),
            "--system-prompt".into(),
            request.system_prompt().into(),
            "--no-session-persistence".into(),
            "--strict-mcp-config".into(),
            "--disable-slash-commands".into(),
        ];
        for (flag, value) in [
            ("--model", &request.options.model),
            ("--effort", &request.options.effort),
        ] {
            if !value.is_empty() {
                args.extend([flag.into(), value.into()]);
            }
        }
        // `--tools` takes a list, so it goes last; the empty list disables every tool.
        args.extend(["--tools".into(), "".into()]);
        args
    }

    fn not_found(&self) -> DraftError {
        DraftError::Unavailable(format!(
            "Claude Code was not found (tried to run `{}`). Install it, or set \"claude_command\" \
in the app's settings.json to its full path.",
            self.command
        ))
    }
}

impl DraftBackend for ClaudeCodeBackend {
    fn name(&self) -> &str {
        "Claude Code"
    }

    fn generate(&self, request: &DraftRequest, cancel: &CancelToken) -> Result<Draft, DraftError> {
        if cancel.is_cancelled() {
            return Err(DraftError::Cancelled);
        }
        let mut child = Command::new(&self.command)
            .args(Self::args(request))
            .current_dir(std::env::temp_dir())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| match e.kind() {
                ErrorKind::NotFound => self.not_found(),
                _ => DraftError::Unavailable(format!("Could not start `{}`: {e}", self.command)),
            })?;

        let mut stdin = child.stdin.take().expect("stdin is piped");
        let ticket = request.ticket_json();
        // Written on its own thread so a large ticket cannot block against a full pipe.
        thread::spawn(move || {
            let _ = stdin.write_all(ticket.as_bytes());
        });
        let stdout = drain(child.stdout.take().expect("stdout is piped"));
        let stderr = drain(child.stderr.take().expect("stderr is piped"));

        let status = wait(&mut child, cancel, self.timeout)?;
        let out = String::from_utf8_lossy(&stdout.join().unwrap_or_default()).into_owned();
        let err = String::from_utf8_lossy(&stderr.join().unwrap_or_default()).into_owned();

        if !status.success() {
            let detail = tail(if err.trim().is_empty() { &out } else { &err });
            return Err(DraftError::Failed(match status.code() {
                Some(code) => format!("Claude Code exited with status {code}. {detail}"),
                None => format!("Claude Code was stopped by a signal. {detail}"),
            }));
        }
        parse_reply(&out)
    }
}

/// Wait for the child, killing it on cancellation or timeout.
fn wait(
    child: &mut Child,
    cancel: &CancelToken,
    timeout: Duration,
) -> Result<std::process::ExitStatus, DraftError> {
    let started = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return Ok(status),
            Ok(None) => {}
            Err(e) => {
                return Err(DraftError::Failed(format!(
                    "Waiting for Claude Code failed: {e}"
                )));
            }
        }
        if cancel.is_cancelled() {
            stop(child);
            return Err(DraftError::Cancelled);
        }
        if started.elapsed() >= timeout {
            stop(child);
            return Err(DraftError::TimedOut(timeout.as_secs()));
        }
        thread::sleep(POLL);
    }
}

fn stop(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

fn drain(mut pipe: impl Read + Send + 'static) -> JoinHandle<Vec<u8>> {
    thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = pipe.read_to_end(&mut buf);
        buf
    })
}

/// The last few hundred characters of some output, for error messages.
fn tail(text: &str) -> String {
    let text = text.trim();
    let skip = text.chars().count().saturating_sub(400);
    text.chars().skip(skip).collect()
}

#[cfg(all(test, unix))]
mod tests {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::path::{Path, PathBuf};

    use super::*;

    /// Tests here write a script and then run it. If another test forks while
    /// the script is still open for writing, the forked child holds it open and
    /// the exec fails with "Text file busy" (ETXTBSY). So tests that spawn
    /// processes run one at a time: the lock is held until the test's thread ends.
    fn serial() {
        use std::cell::RefCell;
        use std::sync::{Mutex, MutexGuard};
        static LOCK: Mutex<()> = Mutex::new(());
        thread_local! {
            static HELD: RefCell<Option<MutexGuard<'static, ()>>> = const { RefCell::new(None) };
        }
        HELD.with(|held| {
            let mut held = held.borrow_mut();
            if held.is_none() {
                *held = Some(LOCK.lock().unwrap_or_else(|e| e.into_inner()));
            }
        });
    }

    /// Writes an executable shell script that stands in for `claude`.
    fn fake_claude(dir: &Path, body: &str) -> PathBuf {
        serial();
        let path = dir.join("claude");
        fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
        path
    }

    fn backend(path: &Path) -> ClaudeCodeBackend {
        ClaudeCodeBackend::new(path.to_string_lossy())
    }

    fn request() -> DraftRequest {
        DraftRequest {
            description: "Add a login page".into(),
            requirements: vec!["Use HTTPS".into()],
            document_prompt: "Plain English.".into(),
            ..Default::default()
        }
    }

    #[test]
    fn sends_system_prompt_and_ticket_json_and_returns_the_draft() {
        let dir = tempfile::tempdir().unwrap();
        let args = dir.path().join("args.txt");
        let stdin = dir.path().join("stdin.txt");
        let script = fake_claude(
            dir.path(),
            &format!(
                "printf '%s\\n' \"$@\" > '{}'\ncat > '{}'\n\
                 echo '```json'\n\
                 echo '{{\"requirements\":[\"Hash passwords\"],\"acceptance_criteria\":[\"Wrong password is rejected\"]}}'\n\
                 echo '```'",
                args.display(),
                stdin.display()
            ),
        );

        let draft = backend(&script)
            .generate(&request(), &CancelToken::new())
            .unwrap();
        assert_eq!(draft.requirements, ["Hash passwords"]);
        assert_eq!(draft.acceptance_criteria, ["Wrong password is rejected"]);

        let args = fs::read_to_string(args).unwrap();
        assert!(args.contains("--system-prompt"), "{args}");
        assert!(
            args.contains("ONLY a JSON object"),
            "system prompt is passed"
        );
        assert!(args.contains("Project writing guidance (follow it):\nPlain English."));
        for flag in [
            "-p",
            "--no-session-persistence",
            "--strict-mcp-config",
            "--tools",
        ] {
            assert!(args.lines().any(|l| l == flag), "missing {flag}: {args}");
        }
        let sent: serde_json::Value =
            serde_json::from_str(&fs::read_to_string(stdin).unwrap()).unwrap();
        assert_eq!(sent["description"], "Add a login page");
        assert_eq!(sent["requirements"][0], "Use HTTPS");
    }

    #[test]
    fn tools_flag_is_followed_by_an_empty_argument() {
        let args = ClaudeCodeBackend::args(&request());
        let at = args.iter().position(|a| a == "--tools").unwrap();
        assert_eq!(args[at + 1], "");
        assert_eq!(at + 2, args.len(), "--tools must be last");
    }

    #[test]
    fn model_and_effort_are_passed_only_when_chosen() {
        let flags = |req: &DraftRequest| -> Vec<String> {
            ClaudeCodeBackend::args(req)
                .iter()
                .map(|a| a.to_string_lossy().into_owned())
                .collect()
        };
        let default = flags(&request());
        assert!(!default.iter().any(|a| a == "--model" || a == "--effort"));

        let mut chosen = request();
        chosen.options.model = "opus".into();
        chosen.options.effort = "high".into();
        let args = flags(&chosen);
        let after = |flag: &str| args[args.iter().position(|a| a == flag).unwrap() + 1].clone();
        assert_eq!(after("--model"), "opus");
        assert_eq!(after("--effort"), "high");
        assert_eq!(args[args.len() - 2], "--tools", "--tools stays last");
    }

    #[test]
    fn a_missing_executable_is_reported_as_unavailable() {
        serial();
        let err = ClaudeCodeBackend::new("/nonexistent/claude")
            .generate(&request(), &CancelToken::new())
            .unwrap_err();
        assert_eq!(err.code(), "unavailable");
        assert!(
            err.to_string().contains("Claude Code was not found"),
            "{err}"
        );
        assert!(err.to_string().contains("claude_command"), "{err}");
    }

    #[test]
    fn a_failing_run_reports_the_exit_status_and_stderr() {
        let dir = tempfile::tempdir().unwrap();
        let script = fake_claude(dir.path(), "echo 'Not logged in' >&2\nexit 3");
        let err = backend(&script)
            .generate(&request(), &CancelToken::new())
            .unwrap_err();
        assert_eq!(err.code(), "failed");
        let msg = err.to_string();
        assert!(
            msg.contains("status 3") && msg.contains("Not logged in"),
            "{msg}"
        );
    }

    #[test]
    fn an_unintelligible_reply_is_a_bad_reply() {
        let dir = tempfile::tempdir().unwrap();
        let script = fake_claude(dir.path(), "cat > /dev/null\necho 'No JSON here'");
        let err = backend(&script)
            .generate(&request(), &CancelToken::new())
            .unwrap_err();
        assert_eq!(err.code(), "bad_reply");
    }

    #[test]
    fn cancelling_stops_a_running_process_quickly() {
        let dir = tempfile::tempdir().unwrap();
        let script = fake_claude(dir.path(), "cat > /dev/null\nexec sleep 30");
        let cancel = CancelToken::new();
        let trigger = cancel.clone();
        thread::spawn(move || {
            thread::sleep(Duration::from_millis(300));
            trigger.cancel();
        });
        let started = Instant::now();
        let err = backend(&script).generate(&request(), &cancel).unwrap_err();
        assert_eq!(err.code(), "cancelled");
        assert!(
            started.elapsed() < Duration::from_secs(5),
            "took {:?}",
            started.elapsed()
        );
    }

    #[test]
    fn a_hung_process_times_out() {
        let dir = tempfile::tempdir().unwrap();
        let script = fake_claude(dir.path(), "cat > /dev/null\nexec sleep 30");
        let started = Instant::now();
        let err = backend(&script)
            .with_timeout(Duration::from_millis(400))
            .generate(&request(), &CancelToken::new())
            .unwrap_err();
        assert_eq!(err.code(), "timeout");
        assert!(started.elapsed() < Duration::from_secs(5));
    }

    #[test]
    fn already_cancelled_requests_do_not_start_a_process() {
        let cancel = CancelToken::new();
        cancel.cancel();
        let err = ClaudeCodeBackend::new("/nonexistent/claude")
            .generate(&request(), &cancel)
            .unwrap_err();
        assert_eq!(err.code(), "cancelled");
    }

    /// Calls the real `claude` CLI (one short request, uses your account).
    /// Run with: cargo test -p stickynotes real_claude -- --ignored --nocapture
    #[test]
    #[ignore = "calls the real Claude Code CLI"]
    fn real_claude_cli_drafts_something() {
        let request = DraftRequest {
            description: "Let users reset a forgotten password by email".into(),
            requirements: vec!["Reset links must expire".into()],
            ..Default::default()
        };
        let draft = ClaudeCodeBackend::new("claude")
            .generate(&request, &CancelToken::new())
            .expect("claude should answer");
        println!("{draft:#?}");
        assert!(
            !draft.acceptance_criteria.is_empty(),
            "expected some acceptance criteria"
        );
    }
}
