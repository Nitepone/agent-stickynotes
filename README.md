# agent-stickynotes

A local, Trello-style kanban board for humans and AI agents. One Rust binary
with a QML UI; while it runs it also serves an MCP server and a REST API on
loopback so Claude Code (or any agent) can read and update the board.

- Boards are JSON files; **File ▸ Export to Markdown** produces a readable copy.
- Columns are an ordered pipeline. Each column's description says what a task
  must satisfy to be there.
- You can drag tasks anywhere. Agents can only create tasks in the first column
  and advance them one column to the right, after checking the next column's
  description.
- Agent write access is **off** by default. Toggle it from the **Agent** menu
  or the pill in the toolbar.

## Build and run

Requires Rust 1.93+ and the Qt 6 development packages (Debian/Ubuntu):

```sh
sudo apt install qt6-base-dev qt6-base-dev-tools qt6-declarative-dev \
  qml6-module-qtquick-dialogs qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtqml-models
export QMAKE=/usr/lib/qt6/bin/qmake6     # if `qmake` is Qt 5
cargo run --release -- [board.json]      # file is created if missing
```

Without a file argument the last board is reopened, otherwise a new board
with default columns is created.

## Using it

| Action | How |
|---|---|
| Add a task | **+** at the bottom of a column |
| Edit a task | Click the sticky note |
| Move a task | Drag the note to a position in any column |
| Delete a task | Drag it onto the trash can (bottom right), or **Delete** in its dialog |
| Draft requirements and criteria | In a task's dialog, **Draft requirements & criteria**. Claude Code proposes new items from the descriptions; review them, then **Save**. Needs `claude` on your PATH. |
| Link tasks | In a task's dialog, **References**: pick a relation and a task, **Add**, then **Save**. The other task shows the matching reverse link. |
| Give agents project instructions | **Board ▸ Project Settings…** (document prompt, code guidance); **Agent ▸ Export Claude Code Skill…** writes them into a `SKILL.md` |
| Edit a column | Click the column title |
| Reorder / add / delete columns | **Edit columns** (toolbar) or **Board ▸ Edit Columns** |
| Save / open / new | **File** menu or toolbar. You are warned before unsaved changes are lost. |

### Drafting with Claude Code

The draft button runs `claude -p` as a subprocess, with no tools, MCP servers or
session history, and sends it a system prompt plus the task as JSON (the
project's document and code guidance are included as context). Nothing is
saved until you click **Save**, existing items are kept, and a draft can be
cancelled. If `claude` is not on your PATH, set `"claude_command"` in
`~/.config/agent-stickynotes/settings.json`. The backend sits behind the
`DraftBackend` trait (`crates/app/src/drafting.rs`), so an Ollama-style endpoint
or local model can be added without touching the UI.

## Connecting Claude Code

See [docs/claude-code-setup.md](docs/claude-code-setup.md). Short version:
open **Agent ▸ Connect Claude Code…**, copy the command, and run it once.

## Development

```sh
cargo test --workspace          # core, API and MCP tests
./scripts/qml-tests.sh          # QML view tests (headless, real mouse drags)
cargo clippy --workspace --all-targets -- -D warnings
cargo test -p stickynotes real_claude -- --ignored   # optional: one real Claude Code call
```

Headless screenshots for UI checks:
`STICKYNOTES_SCREENSHOT=out.png[:scene[:delayMs]] QT_QPA_PLATFORM=offscreen cargo run -- board.json`,
where `scene` is `board`, `edit`, `task`, `newtask`, `column` or `agent`.

### Layout

| Crate | Role |
|---|---|
| `crates/core` | **Model.** Board types, commands, agent rules, `BoardStore` (single write path, revision, dirty flag, change events), JSON persistence, Markdown export. No UI or network code. |
| `crates/server` | **Agent controllers.** `AgentService` plus thin REST (`/api/v1`) and MCP (`/mcp`, Streamable HTTP via `rmcp`) transports, bearer-token auth. |
| `crates/app` | **UI.** `BoardController` (CXX-Qt) turns view intents into commands and republishes store state. `viewmodel.rs` shapes data for QML. `qml/` holds the views. Only `Main.qml` talks to the controller. |

See [PLAN.md](PLAN.md) for the design and milestone status.
