//! A sidecar log of what agents did to the board (`activity.jsonl` in the
//! project folder) and per-day summaries of it for the Activity dialog.
//!
//! The log holds only who, when, what kind of change, the task number and the
//! task's title at that moment: never descriptions or file contents. Writing
//! it is best effort; a failure never fails the board change.

use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Duration, FixedOffset, Utc};
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::command::{Applied, Command, Origin};
use crate::model::{Board, TaskId, card_text};

pub const FILE_NAME: &str = "activity.jsonl";
pub const ROTATED_NAME: &str = "activity.jsonl.1";
/// The log is rotated once it passes this many bytes.
pub const ROTATE_AT: u64 = 1_000_000;
/// Most entries one summary covers (the newest).
const MAX_ENTRIES: usize = 2000;
const TITLE_CHARS: usize = 80;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    /// UTC, RFC 3339.
    pub time: String,
    pub agent: String,
    /// created, updated, advanced, ticked, unticked, deleted, attached, detached.
    pub action: String,
    pub task: u64,
    pub title: String,
    /// For `advanced`: the column the task moved to.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub to: Option<String>,
}

/// What must be read before a command runs because it is gone afterwards.
pub struct Before {
    deleted: Option<(u64, String)>,
    criterion_done: Option<bool>,
}

impl Before {
    pub fn capture(board: &Board, cmd: &Command) -> Before {
        let mut b = Before {
            deleted: None,
            criterion_done: None,
        };
        match cmd {
            Command::DeleteTask { id } => {
                b.deleted = board
                    .task(*id)
                    .map(|t| (t.number, title_of(&t.description)));
            }
            Command::SetCriterion {
                task, criterion, ..
            } => {
                b.criterion_done = board
                    .task(*task)
                    .and_then(|t| t.acceptance_criteria.iter().find(|c| c.id == *criterion))
                    .map(|c| c.done);
            }
            _ => {}
        }
        b
    }
}

fn title_of(description: &str) -> String {
    card_text(description, TITLE_CHARS, 1)
}

/// The entry for an applied command, or `None` for user commands and for
/// commands that are not a recordable agent change.
pub fn entry_for(
    origin: Origin,
    agent: Option<&str>,
    before: &Before,
    cmd: &Command,
    applied: &Applied,
    board: &Board,
    now: DateTime<Utc>,
) -> Option<Entry> {
    if origin != Origin::Agent {
        return None;
    }
    let (action, id): (&str, TaskId) = match (cmd, applied) {
        (Command::CreateTask { .. }, Applied::Task(id)) => ("created", *id),
        (Command::UpdateTask { id, .. }, _) => ("updated", *id),
        (Command::AdvanceTask { id }, _) => ("advanced", *id),
        (Command::SetCriterion { task, done, .. }, _) => {
            if before.criterion_done == Some(*done) {
                return None;
            }
            (if *done { "ticked" } else { "unticked" }, *task)
        }
        (Command::AttachArtifact { task, .. }, _) => ("attached", *task),
        (Command::DetachArtifact { task, .. }, _) => ("detached", *task),
        (Command::DeleteTask { id }, _) => ("deleted", *id),
        _ => return None,
    };
    let (number, title, to) = if action == "deleted" {
        let (n, t) = before.deleted.clone()?;
        (n, t, None)
    } else {
        let (ci, _) = board.locate_task(id)?;
        let t = board.task(id)?;
        let to = (action == "advanced").then(|| board.columns[ci].title.clone());
        (t.number, title_of(&t.description), to)
    };
    let agent = agent
        .map(|a| a.trim().chars().take(80).collect::<String>())
        .filter(|a| !a.is_empty())
        .unwrap_or_else(|| "agent".to_string());
    Some(Entry {
        time: now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
        agent,
        action: action.to_string(),
        task: number,
        title,
        to,
    })
}

/// Append `entry` to the log in `dir`, rotating first if it is full.
/// Errors are returned for callers that care; the store ignores them.
pub fn append(dir: &Path, entry: &Entry) -> std::io::Result<()> {
    append_with_limit(dir, entry, ROTATE_AT)
}

fn append_with_limit(dir: &Path, entry: &Entry, limit: u64) -> std::io::Result<()> {
    let path = dir.join(FILE_NAME);
    if fs::metadata(&path).is_ok_and(|m| m.len() > limit) {
        fs::rename(&path, dir.join(ROTATED_NAME))?;
    }
    let mut line = serde_json::to_string(entry).map_err(std::io::Error::other)?;
    line.push('\n');
    let mut f = OpenOptions::new().create(true).append(true).open(path)?;
    f.write_all(line.as_bytes())
}

/// Entries in `dir`, oldest first: the rotated file, then the current one.
/// Lines that do not parse are skipped; missing files are empty.
pub fn read(dir: &Path) -> Vec<Entry> {
    [ROTATED_NAME, FILE_NAME]
        .iter()
        .filter_map(|n| fs::read_to_string(dir.join(n)).ok())
        .flat_map(|text| {
            text.lines()
                .filter_map(|l| serde_json::from_str::<Entry>(l).ok())
                .collect::<Vec<_>>()
        })
        .collect()
}

pub fn log_path(dir: &Path) -> PathBuf {
    dir.join(FILE_NAME)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DaySummary {
    /// `YYYY-MM-DD` in the offset used.
    pub date: String,
    pub label: String,
    pub changes: usize,
    pub tasks: usize,
    pub agents: Vec<String>,
    /// Count per action, in a fixed order.
    pub counts: Vec<(String, usize)>,
    /// `(HH:MM, text)`, newest first.
    pub entries: Vec<(String, String)>,
}

const ORDER: [&str; 8] = [
    "created", "updated", "advanced", "ticked", "unticked", "attached", "detached", "deleted",
];

fn count_phrase(action: &str, n: usize) -> String {
    match action {
        "ticked" => format!("{n} criteria ticked"),
        "unticked" => format!("{n} criteria unticked"),
        "attached" => format!("{n} {} attached", plural(n, "artifact")),
        "detached" => format!("{n} {} detached", plural(n, "artifact")),
        a => format!("{n} {a}"),
    }
}

fn plural(n: usize, word: &str) -> String {
    if n == 1 {
        word.to_string()
    } else {
        format!("{word}s")
    }
}

fn entry_text(e: &Entry) -> String {
    let what = match e.action.as_str() {
        "advanced" => format!("advanced #{} to {}", e.task, e.to.as_deref().unwrap_or("?")),
        "ticked" => format!("ticked a criterion on #{}", e.task),
        "unticked" => format!("unticked a criterion on #{}", e.task),
        "attached" => format!("attached an artifact to #{}", e.task),
        "detached" => format!("detached an artifact from #{}", e.task),
        a => format!("{a} #{}", e.task),
    };
    if e.title.is_empty() {
        format!("{} {what}", e.agent)
    } else {
        format!("{} {what}: {}", e.agent, e.title)
    }
}

/// Group `entries` by day (at `offset_minutes` east of UTC), newest day first.
/// `now` decides which day is "Today" and "Yesterday".
pub fn summarize(entries: &[Entry], now: DateTime<Utc>, offset_minutes: i32) -> Vec<DaySummary> {
    let offset = FixedOffset::east_opt(offset_minutes * 60)
        .unwrap_or_else(|| FixedOffset::east_opt(0).expect("zero offset"));
    let today = now.with_timezone(&offset).date_naive();
    let skip = entries.len().saturating_sub(MAX_ENTRIES);
    let mut days: BTreeMap<chrono::NaiveDate, Vec<(DateTime<FixedOffset>, &Entry)>> =
        BTreeMap::new();
    for e in &entries[skip..] {
        let Ok(t) = DateTime::parse_from_rfc3339(&e.time) else {
            continue;
        };
        let t = t.with_timezone(&offset);
        days.entry(t.date_naive()).or_default().push((t, e));
    }
    days.into_iter()
        .rev()
        .map(|(date, mut list)| {
            list.sort_by_key(|(t, _)| std::cmp::Reverse(*t));
            let mut counts: BTreeMap<&str, usize> = BTreeMap::new();
            for (_, e) in &list {
                *counts.entry(e.action.as_str()).or_default() += 1;
            }
            let agents: BTreeSet<String> = list.iter().map(|(_, e)| e.agent.clone()).collect();
            let tasks: BTreeSet<u64> = list.iter().map(|(_, e)| e.task).collect();
            let label = if date == today {
                "Today".to_string()
            } else if date == today - Duration::days(1) {
                "Yesterday".to_string()
            } else {
                date.format("%Y-%m-%d").to_string()
            };
            let mut counts_out: Vec<(String, usize)> = ORDER
                .iter()
                .filter_map(|a| counts.get(a).map(|n| (a.to_string(), *n)))
                .collect();
            for (a, n) in &counts {
                if !ORDER.contains(a) {
                    counts_out.push((a.to_string(), *n));
                }
            }
            DaySummary {
                date: date.format("%Y-%m-%d").to_string(),
                label,
                changes: list.len(),
                tasks: tasks.len(),
                agents: agents.into_iter().collect(),
                counts: counts_out,
                entries: list
                    .iter()
                    .map(|(t, e)| (t.format("%H:%M").to_string(), entry_text(e)))
                    .collect(),
            }
        })
        .collect()
}

impl DaySummary {
    /// "Today: 12 changes by claude-code on 5 tasks: 2 created, 3 advanced".
    pub fn line(&self) -> String {
        let parts: Vec<String> = self
            .counts
            .iter()
            .map(|(a, n)| count_phrase(a, *n))
            .collect();
        format!(
            "{}: {} {} by {} on {} {}: {}",
            self.label,
            self.changes,
            plural(self.changes, "change"),
            self.agents.join(", "),
            self.tasks,
            plural(self.tasks, "task"),
            parts.join(", ")
        )
    }
}

/// The JSON the Activity dialog shows: `{"days":[{"label","summary","entries":[{"time","text"}]}]}`.
pub fn to_json(days: &[DaySummary]) -> String {
    let days: Vec<_> = days
        .iter()
        .map(|d| {
            json!({
                "date": d.date,
                "label": d.label,
                "summary": d.line(),
                "entries": d.entries.iter()
                    .map(|(time, text)| json!({"time": time, "text": text}))
                    .collect::<Vec<_>>(),
            })
        })
        .collect();
    json!({ "days": days }).to_string()
}

/// The dialog's JSON for the project in `dir`, in the machine's local time.
pub fn json_for_dir(dir: Option<&Path>) -> String {
    let entries = dir.map(read).unwrap_or_default();
    let now = Utc::now();
    let offset = chrono::Local::now().offset().local_minus_utc() / 60;
    to_json(&summarize(&entries, now, offset))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn e(time: &str, agent: &str, action: &str, task: u64, to: Option<&str>) -> Entry {
        Entry {
            time: time.into(),
            agent: agent.into(),
            action: action.into(),
            task,
            title: "T".into(),
            to: to.map(Into::into),
        }
    }

    #[test]
    fn summary_groups_by_day_and_offset() {
        let entries = vec![
            e("2026-11-02T23:30:00Z", "a", "created", 1, None),
            e("2026-11-03T09:00:00Z", "a", "advanced", 1, Some("Review")),
            e("2026-11-03T10:00:00Z", "b", "ticked", 2, None),
            e("2026-11-03T10:05:00Z", "b", "ticked", 2, None),
        ];
        let now: DateTime<Utc> = "2026-11-03T12:00:00Z".parse().unwrap();
        let days = summarize(&entries, now, 0);
        assert_eq!(days.len(), 2);
        assert_eq!(days[0].label, "Today");
        assert_eq!(days[0].changes, 3);
        assert_eq!(days[0].tasks, 2);
        assert_eq!(
            days[0].line(),
            "Today: 3 changes by a, b on 2 tasks: 1 advanced, 2 criteria ticked"
        );
        assert_eq!(days[0].entries[0].0, "10:05");
        assert!(days[0].entries[2].1.contains("advanced #1 to Review"));
        assert_eq!(days[1].label, "Yesterday");
        // With +2h, the 23:30 entry falls on today's local day.
        let days = summarize(&entries, now, 120);
        assert_eq!(days.len(), 1);
        assert_eq!(days[0].changes, 4);
    }

    #[test]
    fn corrupt_lines_skipped_and_missing_is_empty() {
        let dir = tempfile::tempdir().unwrap();
        assert!(read(dir.path()).is_empty());
        append(
            dir.path(),
            &e("2026-11-03T09:00:00Z", "a", "created", 1, None),
        )
        .unwrap();
        let mut f = OpenOptions::new()
            .append(true)
            .open(dir.path().join(FILE_NAME))
            .unwrap();
        f.write_all(b"not json\n{\"time\":\"x\"\n").unwrap();
        append(
            dir.path(),
            &e("2026-11-03T09:01:00Z", "a", "updated", 1, None),
        )
        .unwrap();
        assert_eq!(read(dir.path()).len(), 2);
    }

    #[test]
    fn rotation_keeps_one_old_file() {
        let dir = tempfile::tempdir().unwrap();
        let en = e("2026-11-03T09:00:00Z", "a", "created", 1, None);
        for _ in 0..3 {
            append_with_limit(dir.path(), &en, 100).unwrap();
        }
        for _ in 0..5 {
            append_with_limit(dir.path(), &en, 100).unwrap();
        }
        assert!(dir.path().join(ROTATED_NAME).exists());
        assert!(!dir.path().join("activity.jsonl.2").exists());
        assert!(fs::metadata(dir.path().join(FILE_NAME)).unwrap().len() <= 100 + 200);
    }

    #[test]
    fn json_shape() {
        let entries = vec![e("2026-11-03T09:00:00Z", "a", "created", 1, None)];
        let now: DateTime<Utc> = "2026-11-03T12:00:00Z".parse().unwrap();
        let v: serde_json::Value =
            serde_json::from_str(&to_json(&summarize(&entries, now, 0))).unwrap();
        assert_eq!(v["days"][0]["entries"][0]["time"], "09:00");
        assert!(
            v["days"][0]["summary"]
                .as_str()
                .unwrap()
                .starts_with("Today: 1 change by a")
        );
    }
}
