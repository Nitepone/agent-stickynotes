# agent-stickynotes

A local, Trello-style kanban board for humans and AI agents. One Rust binary
with a QML UI; while it runs it also serves an MCP server and a REST API on
loopback so Claude Code (or any agent) can read and update the board.

- A board lives in a project folder: `stickynotes.json` plus an `artifacts/` folder
  (for the Markdown and images agents attach to tasks). **File ▸ Export to Markdown**
  produces a readable copy.
- Agents can attach Markdown and image files to tasks (see
  [docs/claude-code-setup.md](docs/claude-code-setup.md#artifacts)); they can add and
  detach artifacts but never delete files.
- Columns are an ordered pipeline. Each column's description says what a task
  must satisfy to be there.
- You can drag tasks anywhere. Agents can only create tasks in the first column
  and advance them one column to the right, after checking the next column's
  description.
- Agent write access is **off** by default. Toggle it from the **Agent** menu
  or the robot icon at the right of the toolbar (yellow: agents can only read, green: they can write).

## Build and run

Requires Rust 1.93+ and the Qt 6 development packages (Debian/Ubuntu):

```sh
sudo apt install qt6-base-dev qt6-base-dev-tools qt6-declarative-dev \
  qml6-module-qtquick-dialogs qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtqml-models
export QMAKE=/usr/lib/qt6/bin/qmake6     # if `qmake` is Qt 5
cargo run --release -- [project-folder]  # a new or empty folder becomes a project
```

Without an argument the last project is reopened; on first run the project
picker opens. Projects are kept by default in your user data folder
(`~/.local/share/agent-stickynotes/projects` on Linux, `~/Library/Application
Support/agent-stickynotes/projects` on macOS, `%APPDATA%\agent-stickynotes\data\projects`
on Windows). The picker lists them, creates new ones, and has **Browse…** for a
folder anywhere else. Boards from before projects are not opened directly: put
the file in a project folder as `stickynotes.json`.

## Using it

| Action | How |
|---|---|
| Add a task | **+** at the bottom of a column |
| Edit a task | Click the sticky note |
| Refer to a task | Every task has a permanent number (`#12`) at the bottom left of the note and in its dialog. Numbers are never reused. Tell an agent "look at #12"; every agent tool accepts `#12` in place of an id. |
| Move a task | Drag the note to a position in any column |
| Delete a task | Drag it onto the trash can (bottom right), or **Delete** in its dialog |
| Draft requirements and criteria | In a task's dialog, **Draft requirements & criteria**. Claude Code proposes new items from the descriptions; review them, then **Save**. Needs `claude` on your PATH. |
| Link tasks | In a task's dialog, **References**: pick a relation and a task, **Add**, then **Save**. The other task shows the matching reverse link. |
| Give agents project instructions | **Board ▸ Project Settings…** (document prompt, code guidance); **Agent ▸ Export Claude Code Skill…** writes them into a `SKILL.md` |
| See what an agent changed | Notes an agent created, moved, edited or ticked criteria on **glow green** at the edges (a highlight circles the note; an edited note also gets a sheen). The glow stays until you are back, then fades over 20 seconds. Your own changes never glow. With reduced motion (Preferences ▸ Personalization ▸ Motion, or the desktop's setting) the glow is still. |
| Change the look | **File ▸ Preferences…** (Ctrl+,) or the gear icon in the toolbar: Personalization has Light/Dark, primary and secondary accent colors and the sticky note color (presets, a hex code, or a picker), plus resets. Text on a note adjusts to stay readable on any color. Changes apply immediately and are remembered. |
| Spell check and the draft agent | Preferences ▸ Editor: turn the red underlines for misspelled words in the task editor on or off, and choose how the draft agent runs (agent type, an extra system prompt, and for Claude Code the model and thinking level). |
| Edit a column | Click the column title |
| Reorder / add / delete columns | the pencil icon (toolbar) or **Board ▸ Edit Columns** |
| Save / open / new | **File ▸ New Project… / Open Project…** (the picker), **File ▸ Save**. A floppy-disk icon appears in the toolbar while there are unsaved changes. You are warned before unsaved changes are lost. |

### Spell check

The task editor underlines misspelled words using a Hunspell dictionary
(`.aff` + `.dic`) for your language (from `LANG`), or American English. It looks
in `/usr/share/hunspell`, `/usr/share/myspell`, Homebrew's and macOS's spelling
folders, a `dictionaries` folder next to the executable (the AppImage ships
`en_US` there), and `$STICKYNOTES_DICT_DIR`. With no dictionary nothing is
underlined, and Preferences ▸ Editor says so. Acronyms, `camelCase`, words with
digits and paths or addresses are not flagged.

### Drafting with Claude Code

The draft button runs `claude -p` as a subprocess, with no tools, MCP servers or
session history, and sends it a system prompt plus the task as JSON (the
project's document and code guidance are included as context). Nothing is
saved until you click **Save**, existing items are kept, and a draft can be
cancelled. Preferences ▸ Editor adds your own system prompt to the built-in one
(which fixes the reply format) and sets Claude Code's `--model` and `--effort`.
If `claude` is not on your PATH, set `"claude_command"` in
`~/.config/agent-stickynotes/settings.json`. The backend sits behind the
`DraftBackend` trait (`crates/app/src/drafting.rs`), so an Ollama-style endpoint
or local model can be added without touching the UI.

## Connecting Claude Code

See [docs/claude-code-setup.md](docs/claude-code-setup.md). Short version:
open **Agent ▸ Connect Claude Code…**, copy the command, and run it once.

## Building release artifacts

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs on pushes to
`main`, pull requests and `v*` tags. Three independent jobs each upload an
artifact named `stickynotes-<version>-<platform>`, where `<version>` is the tag
without its `v`, or the Cargo version plus the short commit (`0.1.0-7ee8067`).
A version tag also attaches all three, with a `SHA256SUMS.txt`, to a GitHub
release.

| Platform | Artifact | Built on |
|---|---|---|
| Linux x86_64 | `.AppImage` | the pinned build container below |
| Windows x86_64 | `.zip` holding `stickynotes.exe` and the Qt DLLs it needs | a Windows runner (MSVC) |
| macOS arm64 | `.dmg` | a macOS runner (`macdeployqt`) |

The Linux build runs in the [`Dockerfile`](Dockerfile) image: Rust 1.93.0 and
Qt 6.8.2 on Debian 13, with the AppImage tools pinned by version and checksum.
To build it locally (needs Docker):

```sh
docker build -t agent-stickynotes-build .
scripts/build-linux-container.sh    # builds the image if needed, then the AppImage
# -> target/container-cache/target/dist/stickynotes-<version>-linux-x86_64.AppImage
```

The AppImage needs glibc 2.41 or newer (Debian 13, Ubuntu 25.04, Fedora 42).

**Windows is built natively, not cross-compiled from the Linux container.** Qt's
tools (`qmake`, `moc`, `rcc`, `qmlcachegen`, `windeployqt`) have to run, and
cxx-qt generates C++ that must compile against Qt for the *target*. A MinGW
cross build would need a MinGW Qt plus host and target Qt kept in step, which
is fragile; on a Windows runner the official MSVC Qt build just works. The
`.exe` is linked as a GUI program (no console window); build with
`WINDOWS_CONSOLE=1` to keep one.

The packaging steps are scripts you can run on the matching OS, with Qt 6
(`qmake`, plus `windeployqt` or `macdeployqt`) on `PATH`:
`scripts/package-windows.sh` (from Git Bash) and `scripts/package-macos.sh`
write to `target/dist/`. The macOS app is ad hoc signed, not notarized, and the
Windows `.exe` is unsigned, so both trigger a first-run warning.

## Development

```sh
cargo test --workspace          # core, API and MCP tests
./scripts/qml-tests.sh          # QML view tests (headless, real mouse drags)
cargo clippy --workspace --all-targets -- -D warnings
cargo test -p stickynotes real_claude -- --ignored   # optional: one real Claude Code call
```

Headless screenshots for UI checks:
`STICKYNOTES_SCREENSHOT=out.png[:scene[:delayMs]] QT_QPA_PLATFORM=offscreen cargo run -- <project-folder>`,
where `scene` is `board`, `edit`, `task`, `newtask`, `column`, `agent`, `project`, `prefs`, `editor`, `note-demo`, `theme-demo`, `theme-reset`, `interact`, `synthetic` or `generate`.

### Layout

| Crate | Role |
|---|---|
| `crates/core` | **Model.** Board types, commands, agent rules, `BoardStore` (single write path, revision, dirty flag, change events), JSON persistence, Markdown export. No UI or network code. |
| `crates/server` | **Agent controllers.** `AgentService` plus thin REST (`/api/v1`) and MCP (`/mcp`, Streamable HTTP via `rmcp`) transports, bearer-token auth. |
| `crates/app` | **UI.** `BoardController` (CXX-Qt) turns view intents into commands and republishes store state. `viewmodel.rs` shapes data for QML. `qml/` holds the views. Only `Main.qml` talks to the controller. |

See [PLAN.md](PLAN.md) for the design and milestone status.
