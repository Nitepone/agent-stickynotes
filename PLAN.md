# agent-stickynotes — Implementation Plan

A local, Trello-style kanban board that runs as a single Rust binary with a QML
UI. Humans use the GUI; AI agents (primarily Claude Code) use an MCP server and
a REST API served by the same process. State is stored as JSON; Markdown is an
export format only.

---

## 1. Requirements (authoritative)

These come from the project owner and override the earlier agent brief.

| # | Requirement |
|---|-------------|
| R1 | Board of tasks moved across custom, **ordered** stages (columns). |
| R2 | Task = sticky-note-sized **description** (required) + optional **extended description**, **requirements**, **acceptance criteria**. |
| R3 | Cards show an acceptance-criteria progress indicator (e.g. `2/5`) when they have criteria. |
| R4 | Every column shows its title. Clicking it opens a popup with editable title + description of what the stage means, with a **Save** button. |
| R5 | Clicking a card opens a popup showing/editing all four task fields, with Save. |
| R6 | Menu bar: at minimum **New**, **Open**, **Save** (plus Save As, Export Markdown, agent toggle). |
| R7 | MCP server + API for agents. Menu option to **enable/disable agent write access**. |
| R8 | Persistence is **JSON**. Menu option to **export to Markdown**. |
| R9 | Move tasks by **dragging** cards. Drag onto a **trash can** to delete, with a confirmation dialog. |
| R10 | **"+"** button at the bottom of each column adds a task. |
| R11 | Column **edit mode**: drag columns to reorder, "+" to add a column, "×" to delete; warn when deleting a non-empty column. |

### What we take / drop from the brief

- **Kept:** Rust core + QML (CXX-Qt), REST as the shared core with MCP as a thin
  layer on top, loopback-only binding with a bearer token, small tool surface,
  board exposed as an MCP resource, atomic writes, one write path, preserving
  unknown fields on round-trip.
- **Changed:** persistence is JSON, not Markdown. Because the GUI owns the
  in-memory board and is the only writer, the "file watcher to merge concurrent
  edits" design is unnecessary. We only detect external modification on save.
- **Deferred:** OpenAPI generation, MCP prompts, human-gated review column,
  git-worktree / agent-spawning features.

### Decisions confirmed by the owner

- **Stage order.** Columns have one explicit order, which changes only in edit
  mode. The **user** can move a task to any column. **Agents** move tasks
  strictly left to right, one column at a time. Before advancing a task, the
  agent must check that it meets the target column's description, which acts as
  the entry criteria for that stage. The core enforces the one-step rule.
- **Description length.** There is no hard limit. **200 characters** is a
  suggested length: the UI shows a soft counter, and the MCP tool descriptions
  mention it. Cards that overflow are truncated with `[...]` at the end.
- **Agent permissions.** Agents can read everything. With write access on, they
  can create, edit and delete tasks, advance them, and tick criteria. Agents
  can never add, delete, reorder or edit columns.
- **Saving.** Saving is explicit and there is no autosave. Agent edits mark the
  board dirty the same way human edits do. If the board has unsaved changes,
  closing the window, New and Open all prompt *Save / Discard / Cancel*.
- **Scope.** There is no headless or serve mode. The API and MCP server run only
  while the GUI is open.

---

## 2. Architecture

```
┌──────────────────────── stickynotes (one process) ────────────────────────┐
│                                                                           │
│  QML UI  ◄──signals── BoardController (CXX-Qt QObject) ──calls──┐         │
│                                                                 ▼         │
│                                                     ┌──────────────────┐  │
│  tokio runtime (background thread)                  │  BoardStore      │  │
│  ┌──────────────────────────────┐   calls           │  (core crate)    │  │
│  │ axum on 127.0.0.1:<port>     │──────────────────►│  Mutex<Session>  │  │
│  │  /api/v1/...  (REST)         │                   │  - Board         │  │
│  │  /mcp         (rmcp, HTTP)   │                   │  - path, dirty   │  │
│  └──────────────────────────────┘                   │  - revision      │  │
│                                                     │  - agent_write   │  │
│                                                     └────────┬─────────┘  │
│                                                              │ change     │
│                                    queue to Qt thread ◄──────┘ events     │
└───────────────────────────────────────────────────────────────────────────┘
        ▲ Streamable HTTP MCP                    ▲ stdio
        │                                        │
   Claude Code  ◄── or ── `stickynotes mcp` (stdio→HTTP bridge subprocess)
```

### Key decisions

1. **One write path.** Every mutation (from QML or from the API) is a
   `core::Command` applied by `BoardStore::apply(origin, cmd)`. It validates,
   bumps `revision`, sets `dirty`, and emits a change event. The UI never edits
   its own copy of the board.
2. **The GUI hosts the API and MCP (brief option 3, simplified).** axum serves
   REST and rmcp's Streamable HTTP MCP service on the same loopback port, both
   calling the same service layer. Claude Code connects directly with
   `claude mcp add --transport http`. A `stickynotes mcp` stdio subcommand is a
   thin bridge for clients that only support stdio. It finds the running GUI
   through a runtime discovery file. Built last; optional.
3. **Agent rules are enforced in the core**, not in the MCP layer. If the
   toggle is off, `apply(Origin::Agent, _)` returns `Error::AgentWriteDisabled`.
   It returns `Error::AgentNotPermitted` for column commands, for moves other
   than one step right, and for creating a task anywhere but the first column.
   REST maps these errors to `403`, and MCP maps them to tool errors with a clear
   message. Reads are always allowed.
4. **Optimistic concurrency.** The board has a monotonically increasing
   `revision`. Agent write calls may pass `expected_revision`. A mismatch returns
   `409` / a tool error, so an agent working from stale state re-reads instead of
   overwriting a human's change.
5. **UI binding: JSON snapshot first.** `BoardController` exposes a `boardJson`
   property plus `Q_INVOKABLE` mutation methods. QML parses the snapshot into JS
   arrays used as `Repeater` models. For dozens of cards this is simple and fast,
   and it avoids nested `QAbstractListModel`s in CXX-Qt, which are the riskiest
   part of the stack. The boundary is narrow, so we can swap to real list models
   later if animation or performance requires it.
6. **Security.** Bind to `127.0.0.1` only. Use a random bearer token generated on
   first run and stored at `$XDG_CONFIG_HOME/agent-stickynotes/token` (mode
   `0600`). Every request requires `Authorization: Bearer <token>`. Validate the
   `Host` / `Origin` headers to block DNS-rebinding requests from browsers.
7. **Single binary caveat.** Qt is dynamically linked. "Single binary" means
   one executable plus the system Qt 6 runtime. Static Qt is out of scope for the
   prototype.

---

## 3. Repository layout

```
agent-stickynotes/
├── Cargo.toml                 # workspace; pinned versions
├── crates/
│   ├── core/                  # no Qt, no tokio. Pure model + logic.
│   │   └── src/{model.rs, command.rs, store.rs, persist.rs, export_md.rs, error.rs}
│   ├── server/                # axum REST + rmcp MCP; depends on core
│   │   └── src/{lib.rs, rest.rs, mcp.rs, auth.rs, discovery.rs}
│   └── app/                   # the `stickynotes` binary: CXX-Qt + CLI
│       ├── build.rs           # cxx-qt-build, registers QML module
│       ├── src/{main.rs, controller.rs, settings.rs, bridge_stdio.rs}
│       └── qml/
│           ├── Main.qml               # ApplicationWindow + MenuBar + toolbar
│           ├── BoardView.qml          # horizontal ListView/Row of columns
│           ├── ColumnView.qml         # header, cards, "+" button, edit chrome
│           ├── TaskCard.qml           # sticky note + progress badge
│           ├── TaskDialog.qml         # 4-field editor
│           ├── ColumnDialog.qml       # title + description editor
│           ├── TrashCan.qml           # DropArea + confirm
│           └── ConfirmDialog.qml
├── docs/claude-code-setup.md
└── PLAN.md
```

### Dependencies (latest as of 2026-10-29; pin exact versions in `Cargo.toml`)

| Crate | Version | Use |
|-------|---------|-----|
| `cxx-qt`, `cxx-qt-lib`, `cxx-qt-build` | 0.10.0 | Rust ↔ QML. Pin exactly (`=0.10.0`); the API changes between minors. |
| `rmcp` | 3.8.0 | Official Rust MCP SDK: server, Streamable HTTP transport, stdio client for the bridge. |
| `axum` | 0.8.x | REST + mounting the MCP service. |
| `tokio` | 1.x | Async runtime on a background thread. |
| `serde`, `serde_json` | 1.x | Model + persistence. |
| `uuid` | 1.x (v4, serde) | Stable IDs. |
| `thiserror`, `anyhow` | — | Errors (core / app). |
| `clap` | 4.x | `stickynotes [FILE]`, `stickynotes mcp`. |
| `directories` | — | XDG config paths. |
| dev: `insta`, `tempfile`, `tower` (`ServiceExt::oneshot`), `reqwest` | — | Snapshot, I/O, and HTTP tests. |

Check rmcp's Streamable HTTP server feature names and axum integration against
its docs and examples during M0. Its API has changed across major versions.

### System prerequisites (Debian 13, this machine)

Only the Qt 6 **runtime** packages are installed now. Building needs:

```sh
sudo apt install qt6-base-dev qt6-base-dev-tools qt6-declarative-dev \
  qml6-module-qtquick-dialogs qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtqml-models
export QMAKE=/usr/lib/qt6/bin/qmake6   # system `qmake` is Qt 5.15
```

---

## 4. Data model & JSON format

```rust
struct Board {
    schema_version: u32,          // = 1
    id: Uuid,
    title: String,
    columns: Vec<Column>,         // Vec order IS the stage order
    #[serde(flatten)] extra: Map<String, Value>,   // preserve unknown fields
}
struct Column {
    id: Uuid,
    title: String,                // non-empty
    description: String,          // "what this stage means" = entry criteria agents must check
    tasks: Vec<Task>,             // Vec order = card order in column
    #[serde(flatten)] extra: Map<String, Value>,
}
struct Task {
    id: Uuid,
    description: String,          // required, non-empty after trim; ~200 chars suggested, not enforced
    extended_description: String, // optional (empty = absent), markdown-ish text
    requirements: Vec<String>,
    acceptance_criteria: Vec<Criterion>,
    created_at: DateTime<Utc>, updated_at: DateTime<Utc>,
    #[serde(flatten)] extra: Map<String, Value>,
}
struct Criterion { id: Uuid, text: String, done: bool }
```

- Nesting tasks inside columns keeps the JSON readable and makes ordering
  implicit. Lookup by task ID is a linear scan, which is fine at this size.
- `revision`, `dirty`, `path`, and `agent_write` are **session** state in
  `BoardStore`, not persisted in the board file.
- **Writes are atomic:** serialize to a temporary file in the same directory,
  `fsync`, then `rename`. Record the file's mtime and hash on load and save. On
  Save, if the file on disk has changed, ask whether to overwrite or Save As.
- **Agent write toggle** persists in app settings
  (`$XDG_CONFIG_HOME/agent-stickynotes/settings.json`, along with recent files
  and the port). It **defaults to off** on first run.
- **New board** template columns: *Backlog*, *To Do*, *In Progress*, *Review*,
  *Done*, each with a one-line description.

### Commands (the only way to mutate)

`CreateTask{column, position?, fields}`, `UpdateTask{id, patch}`,
`MoveTask{id, to_column, position}`, `AdvanceTask{id}`, `DeleteTask{id}`,
`SetCriterion{task, criterion, done}`,
`CreateColumn{position, title, description}`, `UpdateColumn{id, patch}`,
`MoveColumn{id, position}`, `DeleteColumn{id, force}`, `RenameBoard{title}`.

`DeleteColumn` without `force` fails on a non-empty column, and the UI uses that
failure to show its warning.

**Agent restrictions** (enforced in `BoardStore::apply` for `Origin::Agent`):
- Agents cannot issue any column command or `RenameBoard`.
- `MoveTask` must target the column immediately to the right of the task's
  current column. Agents can't move tasks backwards, skip columns or reorder
  within a column. Agents use a convenience command, `AdvanceTask{id}`, which
  moves the task to the end of the next column.
- `CreateTask` always places the task in the first (leftmost) column.
- A task in the last column cannot be advanced.

---

## 5. UI design (QML)

**Window:** `ApplicationWindow` with a `MenuBar`, a slim toolbar, and the board
in a horizontally scrolling `ListView`. The title shows `board title — file name`
plus `•` when there are unsaved changes.

**Menus**
- **File:** New (Ctrl+N), Open… (Ctrl+O), Open Recent ▸, Save (Ctrl+S),
  Save As… (Ctrl+Shift+S), Export Markdown… (Ctrl+E), Quit (Ctrl+Q).
  New, Open, Quit, and closing the window prompt *Save / Discard / Cancel* when
  the board has unsaved changes (`onClosing` sets `close.accepted = false` until
  the user answers).
- **Board:** Edit Columns (toggle), Rename Board…
- **Agent:** ☑ Allow agent write access; Copy Claude Code setup command; Show
  API endpoint & token…
- The toolbar mirrors the main actions. A status pill (`Agent: read-only` /
  `Agent: read-write`) makes the agent's current access visible at a glance.

**Columns (normal mode)**
- Header: column title (click opens `ColumnDialog`) and a task count.
- Card list, then a full-width **"+"** button at the bottom. It opens
  `TaskDialog` in create mode for that column.

**Cards (`TaskCard.qml`)**
- Fixed width, sticky-note look: pastel fill and a slight shadow. The
  description is clamped to about 4 lines or 200 characters. If it is longer, it
  is cut at a word boundary and `[...]` is appended. A Rust helper produces this
  text so it can be unit-tested, rather than relying on QML elide, which only
  shows `…`.
- If there are acceptance criteria: a small bar and a `✓ 2/5` badge. The badge
  turns green when all criteria are done. Nothing is shown when there are no
  criteria.
- Click opens `TaskDialog`. A `DragHandler` lets you drag the card. While
  dragging, a `Drag.keys: ["task"]` proxy follows the cursor.

**Drag & drop**
- Each column's card list is a `DropArea` (keys `task`). The insertion index is
  computed from the drop y-position against the card delegates, and a
  placeholder gap previews where the card will land. On drop the UI calls
  `controller.moveTask(id, columnId, index)`.
- **Trash can:** a fixed icon in the bottom-right corner (also a `DropArea`, keys
  `task`). It is highlighted while you drag over it. Dropping a card opens
  `ConfirmDialog`: "Delete task '<description>'?" with Delete / Cancel.

**Task dialog (`TaskDialog.qml`)**
- Description `TextArea` (short): required, so Save is disabled while it is
  empty. A soft `n/200 suggested` counter turns amber past 200 characters but
  does not block saving.
- Extended description `TextArea`.
- Requirements: an editable list of rows with "+ Add" and a "×" per row.
- Acceptance criteria: an editable list of `CheckBox` + text rows, with
  "+ Add" and "×".
- Buttons: Save / Cancel. Cancel discards edits. Optionally a Delete button,
  which reuses the trash-can confirmation.

**Column dialog (`ColumnDialog.qml`)**
- Title `TextField` (required) and description `TextArea`, with Save / Cancel.

**Edit mode (Board ▸ Edit Columns or a toolbar toggle)**
- Card dragging and the per-column "+" are disabled. Columns get a tinted header,
  a drag grip, and an **×** button.
- Drag a column by its grip. A `DropArea` between columns shows an insertion bar,
  and dropping calls `moveColumn`.
- A **"+ Add column"** placeholder column at the end opens `ColumnDialog` in
  create mode.
- × on an empty column deletes it immediately (or after a light confirmation).
  On a non-empty column it shows a **warning**: "Column 'X' contains N tasks.
  Deleting it will delete them. Continue?"
- A **Done** button exits edit mode.

**Live updates:** when an agent changes the board, the store emits a change event
→ `CxxQtThread::queue` → `boardChanged` signal → QML re-reads `boardJson`. If a
dialog is open on a task that the agent changes, show an inline banner: "This
task was changed by an agent — reload?". Don't silently overwrite the user's
in-progress edits.

---

## 6. REST API (`/api/v1`, loopback, bearer token)

| Method | Path | Notes |
|--------|------|-------|
| GET | `/board` | Full board + `revision` + `agent_write` flag. |
| GET | `/columns` | Ordered list: id, title, description, task count. |
| GET | `/tasks?column=<id\|title>` | Summaries (id, description, criteria progress). |
| GET | `/tasks/{id}` | Full task, plus its current column and the **next column's title and description**, so the agent can check entry criteria before advancing. |
| POST | `/tasks` | `{description, extended_description?, requirements?, acceptance_criteria?}`. Always created in the first column. |
| PATCH | `/tasks/{id}` | Partial update. |
| POST | `/tasks/{id}/advance` | Moves the task to the end of the next column. Fails in the last column. |
| PUT | `/tasks/{id}/criteria/{cid}` | `{done}` |
| DELETE | `/tasks/{id}` | |
| GET | `/export/markdown` | `text/markdown` |

- In filters, columns may be referenced by ID or by exact (case-insensitive)
  title. An ambiguous title returns a `400` that lists the matching columns.
- There are no column write endpoints, because agents cannot modify columns.
- Write requests accept an optional `If-Match: <revision>` header (REST) or an
  `expected_revision` argument (MCP).
- Errors are JSON `{error, message}`. Status codes: `400` validation, `403` agent
  write disabled, `404` not found, `409` revision conflict, `503` no board open.
- Port: setting with default `7317`; if busy, fall back to an OS-assigned port.
  On startup, write `runtime.json` (`{port, pid}`) to the runtime directory.

## 7. MCP server (`/mcp`, Streamable HTTP; same handlers as REST)

**Tools (8):** `board_get`, `task_list`, `task_get`, `task_create`,
`task_update`, `task_advance`, `task_delete`, `criterion_set`.
Tool names are flat `snake_case`. The `task_create` and `task_update`
descriptions suggest keeping `description` around 200 characters and putting
detail in `extended_description`. The `task_advance` description tells the agent
to read the next column's description from `task_get` and confirm the task meets
it before calling.

**Resources:** `stickynotes://board` (JSON) and `stickynotes://board.md`
(Markdown). Send resource-updated notifications on change if rmcp's transport
supports it.

**Server instructions** (MCP `instructions` field) cover:
- Columns are an ordered pipeline. Each column's description is the bar a task
  must meet to enter it.
- Agents advance tasks one column at a time, left to right, only after checking
  the criteria themselves. Only the human moves tasks backwards or skips columns.
- New tasks start in the first column.
- Tick acceptance criteria as you go.
- The human may turn write access off at any time.

**Claude Code registration** (documented in `docs/claude-code-setup.md`; the
Agent menu copies it with the real token):

```sh
claude mcp add --transport http --scope user stickynotes \
  http://127.0.0.1:7317/mcp --header "Authorization: Bearer <token>"
# stdio alternative (bridge reads token + port itself):
claude mcp add --scope user stickynotes -- stickynotes mcp
```

## 8. Markdown export

Export is deterministic and one-way. It is never read back.

```markdown
# <Board title>

## <Column title>
> <column description>

### <task description>
<extended description>

**Requirements**
- …

**Acceptance criteria** (2/3)
- [x] …
- [ ] …
```

Snapshot-test the output with `insta`.

---

## 9. Milestones

Each milestone ends with `cargo fmt --check`, `cargo clippy -D warnings`, and
`cargo test` passing, plus a commit.

| M | Scope | Done when |
|---|-------|-----------|
| **M0 — Scaffold & de-risk** | Workspace, pinned deps, Qt dev packages installed. **CXX-Qt spike:** window with `MenuBar`, one QObject property, one invokable, one signal queued from a tokio thread. **rmcp spike:** a single-tool Streamable HTTP server mounted in axum, connected from `claude mcp add`. | Both spikes run on this machine. API notes recorded in the repo. |
| **M1 — Core** | Model, validation, `Command`s, `BoardStore` (revision, dirty, agent gate, change events), atomic JSON load/save with unknown-field preservation, Markdown export. | Unit tests for every command and invariant. JSON round-trip test with unknown fields. Markdown snapshot test. |
| **M2 — UI shell** | `BoardController`, menus (New / Open / Save / Save As / Export / Quit), dirty tracking + prompts, read-only rendering of columns and cards with progress badges. | Can open, save, and create boards, and they look right. |
| **M3 — UI editing** | `TaskDialog`, `ColumnDialog`, "+" add task, card drag-and-drop with insertion preview, trash can + confirmation. | Requirements R2–R5, R9, and R10 demoable. |
| **M4 — Column edit mode** | Toggle, column drag reorder, add column, delete with non-empty warning. | R11 demoable. |
| **M5 — REST API** | axum on a background tokio runtime, auth + Host check, endpoints, agent-write menu toggle + status pill, live UI refresh, conflict banner in dialogs. | Integration tests via `tower::oneshot`. `curl` edits appear live in the GUI. Writes return `403` when the toggle is off. |
| **M6 — MCP** | rmcp tools / resources / instructions over Streamable HTTP. Agent menu "copy setup command". `docs/claude-code-setup.md`. | An in-process rmcp client test passes. A real Claude Code session moves a card and ticks a criterion. |
| **M7 — Polish** | `stickynotes mcp` stdio bridge, recent files, external-modification check on save, keyboard shortcuts, card colors, README. | Done-criteria checklist (below) passes. |

### Testing strategy

- **Core:** most of the logic lives here, so most tests do too: command semantics,
  position clamping, validation errors, the agent gate, the agent rules (column
  commands refused, only one-step-right moves, creation in the first column),
  `[...]` truncation, revision conflicts, and
  property tests for move/reorder invariants (no lost or duplicated tasks).
- **Server:** HTTP-level tests against a router built over a temporary store, and
  MCP tests with rmcp's client over an in-memory or HTTP transport.
- **UI:** keep logic out of QML. Most UI behavior is verified through
  `BoardController` unit tests (Rust) plus a written manual QA checklist per
  milestone. `qmltestrunner` is optional later.

### Final done criteria

- [ ] New / Open / Save / Save As / Export Markdown work. Unsaved-changes prompts work.
- [ ] Drag a card between and within columns. Drag a card to the trash, confirm, and it is gone.
- [ ] "+" adds a card. A card popup edits all four fields, and description is enforced.
- [ ] Clicking a column title edits its title and description, with Save.
- [ ] Edit mode: reorder, add, and delete columns, with a warning for non-empty columns.
- [ ] Progress badge reflects criteria.
- [ ] Claude Code (HTTP and stdio) can read the board, create and update tasks, advance them one column right, and tick criteria. All writes are refused when the toggle is off. Backward, skipping and column operations are always refused.
- [ ] Long descriptions show `[...]` on the card.
- [ ] Closing with unsaved changes prompts the user.
- [ ] Agent edits show up live and never clobber an open dialog silently.

---

## 11. Status (2026-10-29): initial prototype

**Done:** M0–M6, plus parts of M7.
- The CXX-Qt 0.10 and rmcp 3.8 test builds worked on Debian 13 with Qt 6.8.2.
- Core model, commands, agent rules, store, atomic JSON persistence and Markdown export are done (29 unit tests).
- REST + MCP over Streamable HTTP with bearer auth are done (6 integration tests, including a real rmcp client session).
- QML UI covers every requirement R1–R11. View tests drive real mouse drags through `qmltestrunner` (`scripts/qml-tests.sh`, 10 tests).
- Agent edits show up in the UI live. An open task dialog shows a "changed while editing" banner with Reload.
- On save, the app detects if the file changed on disk and offers to overwrite. The last board is reopened on launch.

**Deviations from the plan above:**
- A board is always open (startup creates a default one), so the API never returns `503`.
- The REST API has no column endpoints, since agents cannot modify columns.
- Added **Board ▸ Rename Board…**.

**Not done yet (M7 leftovers):**
- `stickynotes mcp` stdio bridge (Claude Code uses the HTTP transport directly).
- "Open Recent" menu.
- Auto-scrolling a column vertically while dragging. Horizontal board auto-scroll is done.
