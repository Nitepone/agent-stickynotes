# AGENTS.md

Guidance for AI agents (and people) working in this repository. `README.md` covers
what the app does for users and `PLAN.md` the design; this file is about how to
change the code without breaking it.

agent-stickynotes is a local kanban board: a Rust core, a CXX-Qt/QML UI, and a
loopback REST + MCP server that lets agents read and update the board.

## Build and check

```sh
export QMAKE=/usr/lib/qt6/bin/qmake6        # the default `qmake` here is Qt 5; builds fail without this
cargo fmt --all
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace                      # core, server (REST + real MCP client) and app tests
./scripts/qml-tests.sh                      # QML view tests, headless, real mouse events
```

Run all four before committing; they are fast. The app crate rebuilds C++ glue, so
the first build after touching `controller.rs` or `cpp/` takes about a minute.

`cargo test -p stickynotes real_claude -- --ignored` makes one real call to the
`claude` CLI. It is opt-in; do not run it as part of routine checks.

## Layout and the one rule that matters

| Crate | Role |
|---|---|
| `crates/core` | Model, commands, agent rules, `BoardStore`, JSON persistence, Markdown export, `agent_guide`. No UI or network code. |
| `crates/server` | `AgentService` plus thin REST (`/api/v1`) and MCP (`/mcp`) transports. |
| `crates/app` | `BoardController` (CXX-Qt), `viewmodel.rs`, settings, drafting (LLM), `qml/` views. |

**Every change to a board is a `Command` applied through `BoardStore::apply`** (UI
and agents alike). Do not mutate a `Board` anywhere else. `apply` validates,
bumps the revision, marks the board unsaved and notifies listeners, and
`ops::execute` enforces the agent rules and records `agent_change` markers.

Agents (`Origin::Agent`) may: create tasks in the first column, update tasks, advance a
task exactly one column right, tick criteria, delete tasks. They may never touch
columns, the board title or project settings. Those rules live in
`ops::check_agent_rules`; do not re-implement them in a transport.

## Conventions

- **Data compatibility.** Board and settings files from older versions must keep
  loading. New fields get `#[serde(default)]`, and optional ones
  `skip_serializing_if`. Every board type has an `extra` map that preserves unknown
  fields; keep it. Add a test that an old file still loads.
- **Task numbers** (`#12`) come from `Board::take_number`, only increase and are never
  reused. `Board::normalize` backfills and repairs; it runs on open and marks the
  board unsaved.
- **One source for what agents are told.** The workflow rules, tool list and skill
  text are in `core/src/agent_guide.rs` and feed the MCP instructions and the exported
  skill. A server test checks the tool list matches the tools served; when you add
  or rename a tool, update `agent_guide::TOOLS` and `docs/claude-code-setup.md`.
- **Task references** may be an id or `#N`; resolve them with `AgentService::resolve_task`.
- **QML structure.** Views emit signals; **only `Main.qml` talks to the controller**.
  Keep logic out of QML when it can live in Rust (`viewmodel.rs`) or in a small
  testable QML object (`GlowTracker`, `Theme`).
- **Colors.** Every color is a token in `qml/Theme.qml`. A Rust test
  (`theme::tests::views_do_not_hard_code_colors`) fails on hex colors, named colors
  or `Qt.rgba`/`Qt.color` in any other QML file. Text/background pairs are
  contrast-tested (WCAG AA) in both modes; add new pairs to `tst_theme.qml`.
- **New QML files** must be listed in `crates/app/build.rs`.
- **Settings** (`~/.config/agent-stickynotes/settings.json`) are validated on load and
  fall back to defaults; keep it that way.

## Gotchas that have already cost time

- **Do not name a QML property `on` + capital letter** (`onPrimary`): it is parsed as a
  signal handler and its binding silently never runs. Use `textOnPrimary`.
- **CXX-Qt:** a `#[qproperty(T, name)]` generates `set_name`; an invokable with the same
  Rust name fails with "defined multiple times" (hence `choose_theme_mode`). cxx-qt
  signal/property names become camelCase in QML.
- **Never use `HoverHandler`/`PointHandler` to detect user activity.** A handler on a
  top item swallows hover from the views below; underneath, it never sees hover over
  cards. User input is observed by an application event filter in `cpp/activity.h`.
- **`Qt.quit()` closes the window**, which stops at the "unsaved changes" prompt if the
  board is unsaved. The dev screenshot hook sets `closeConfirmed` for that reason.
- **Opening an old board backfills task numbers and marks it unsaved**: that is
  expected, not a bug.
- **`Date`/clock tests:** `GlowTracker` takes explicit timestamps; use them rather than
  waiting. Stop its `ticker` in tests that use fake times.
- **`pgrep -f`/`pkill` match other processes**, including `timeout` wrappers and the
  user's running app. Track only the PID of what you started (`cmd & pid=$!`).

## Checking UI work without a display

`QT_QPA_PLATFORM=offscreen` works. Set `STICKYNOTES_SCREENSHOT=out.png:<scene>[:delayMs]`
and run `cargo run -p stickynotes -- <project-folder>`: it renders to a PNG and exits.
Scenes: `board`, `projects`, `edit`, `task`, `newtask`, `column`, `agent`, `project`, `prefs`,
`editor`, `note-demo`, `theme-demo`, `theme-reset`, `generate`, `interact`, `synthetic`. Always point
`XDG_CONFIG_HOME` at a scratch directory (settings, the API token and
`last_project` live there) and set `XDG_DATA_HOME` too (the projects folder is under it); use a copy of
a project, never the user's real ones.
Read the PNG to check the result. `STICKYNOTES_REDUCE_MOTION=1` forces reduced motion.
Screenshots and view tests do not prove a drag or click feels right on a real
desktop; say so when that is what you could not check.

## Working on the user's board (MCP)

The `stickynotes` MCP server is the user's live board. Follow the rules it gives you:
call `project_get` first, advance a task only after checking the next column's
description against it, tick criteria as you complete them, and write nothing if write
access is off. Do not move a task into Done: that is the user's acceptance. Reconnecting
after the app restarts needs `/mcp`; the port falls back to a random one if 7317 is
busy, so re-register with the command in **Agent ▸ Connect Claude Code…**. Do not read the
API token from the config directory to work around a failed connection.

## Commits

- One logical change per commit, with a message explaining what and why.
- Tests, docs (`README.md`, `docs/claude-code-setup.md`) and the code ship together.
- Do not commit editor files (`.qmlls.ini`) or build output (`target/`).
- Do not push, tag or rewrite history unless asked.
