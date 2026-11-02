# Connecting an agent

The app serves an MCP server over Streamable HTTP at `http://127.0.0.1:7317/mcp`
while its window is open. If port 7317 is busy, it uses a free port instead; the
**Agent ▸ Connect Agent…** dialog always shows the real address.

Every request needs a bearer token. It is generated on first launch and stored in
`~/.config/agent-stickynotes/token` (mode 0600). The dialog's snippets already
contain it, so treat them (and any file you paste them into) as secret.

## 1. Connect a client (once)

Open **Agent ▸ Connect Agent…**. It has one collapsible section per client; they
open and close independently, and each shows only that client's steps.
**Test connection** in a section asks the app's own endpoint for the project with
the token. "Connected" means the endpoint is reachable and the token is accepted;
it does not see the client's configuration. On failure the section shows the
error and **Retry**.

### Claude Code CLI

Click **Copy command** and run it in a terminal:

```sh
claude mcp add --transport http --scope user stickynotes \
  http://127.0.0.1:7317/mcp --header "Authorization: Bearer <token>"
```

This text is unchanged from earlier versions, so a registration made then keeps
working.

### Claude Code Desktop (no CLI needed)

The desktop app's Code tab loads MCP servers from `~/.claude.json`, a project's
`.mcp.json` and `claude_desktop_config.json`. The simplest way without the `claude`
command is a `.mcp.json` in the project folder you open in the Code tab:

```json
{
  "mcpServers": {
    "stickynotes": {
      "type": "http",
      "url": "http://127.0.0.1:7317/mcp",
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

Approve the server when the Code tab asks. Keep `.mcp.json` out of version control.

The chat tab (and `claude_desktop_config.json` in general) starts local programs
only, so it needs the `mcp-remote` bridge, which requires **Node.js** (`npx`):

```json
{
  "mcpServers": {
    "stickynotes": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://127.0.0.1:7317/mcp", "--allow-http",
               "--header", "Authorization:${AUTH_HEADER}"],
      "env": { "AUTH_HEADER": "Bearer <token>" }
    }
  }
}
```

The file is `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS),
`%APPDATA%\Claude\claude_desktop_config.json` (Windows) or
`~/.config/Claude/claude_desktop_config.json` (Linux); **Settings ▸ Developer ▸
Edit Config** opens it. Restart Claude afterwards. Claude's "custom connectors"
are for remote servers on the internet and cannot reach a loopback address.

Sources: <https://code.claude.com/docs/en/desktop> (Code tab and
`claude_desktop_config.json`), <https://code.claude.com/docs/en/mcp> (`.mcp.json`
format), <https://modelcontextprotocol.io/docs/develop/connect-local-servers>
(config file locations), <https://github.com/geelen/mcp-remote> (bridge and header
syntax).

### OpenCode

Add to `opencode.json` in the project root, or `~/.config/opencode/opencode.json`
for every project:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "stickynotes": {
      "type": "remote",
      "url": "http://127.0.0.1:7317/mcp",
      "enabled": true,
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

Sources: <https://opencode.ai/docs/mcp-servers/>, <https://opencode.ai/docs/config/>.

## 2. Allow writes (when you want them)

Agents can always read. To let them create, edit or move tasks, enable
**Agent ▸ Allow Agent Write Access** (or click the yellow robot icon in the
toolbar). The setting is remembered. While it is off, write tools return an
error that tells the agent to ask you.

## What the agent can do

| Tool | Purpose |
|---|---|
| `project_get` | The project's instructions from **Board ▸ Project Settings…**: how to write documents and code. Agents are told to call it first |
| `board_get` | Columns in order (with their entry criteria), task summaries, revision, write flag |
| `task_list` | Task summaries, optionally for one column (id or title) |
| `task_get` | Full task plus `next_column` (where `task_advance` would move it, with its criteria) |
| `task_create` | New task (optionally with a `category`); always lands in the first column |
| `task_update` | Change description, extended description, requirements, criteria, `category` (empty string clears), and `references` (links to other tasks: `blocks`, `blocked_by`, `relates_to`, `duplicates`, `duplicated_by`; the other task gets the mirrored relation) |
| `task_advance` | Move one column to the right; the agent must check `next_column.description` first |
| `task_delete` | Delete a task |
| `criterion_set` | Tick or untick an acceptance criterion |
| `artifact_add` | Attach a Markdown (`.md`) or image (`.png .jpg .gif .webp .svg`) file to a task, as `content` (text) or `content_base64` |
| `artifact_get` | Read an attached artifact: text for Markdown and SVG, metadata and path for other images |
| `artifact_detach` | Detach an artifact from a task; the file stays in `artifacts/` |

Every task has a permanent number shown as `#12`. Every tool (and the REST paths) accepts `#12` or `12` wherever a task id is expected, and task views include `number`, so you can say "look at #12" and the agent can find it. Numbers are never reused after a task is deleted.

Resources: `stickynotes://board` (JSON) and `stickynotes://board.md` (Markdown).

Agents cannot move tasks backwards, skip columns, or change columns at all;
the core enforces this. All write tools accept `expected_revision`, and a
mismatch means the board changed and the agent should re-read it.

**Size limits.** Writes are capped so a runaway agent (or a huge paste) cannot bloat the board file: a description is at most 2,000 characters, an extended description 50,000, each requirement or criterion 1,000; a task holds at most 100 requirements, 100 criteria and 50 references, and a board at most 2,000 tasks. The same limits apply to your own edits, and a write over a limit is refused with an error naming it (for example "description is 2413 characters; the limit is 2000"). A board that is already over a limit still loads and can be edited downward. Agents are told the limits in the MCP instructions and the exported skill. The numbers are in `crates/core/src/limits.rs`.

Notes you change through these tools glow in the window until the user is back, so changes are easy to spot; the user's own edits clear the glow.

Agent edits appear in the window immediately and count as unsaved changes.
Save the board to keep them.

## Artifacts

Agents attach documents and diagrams to a task with `artifact_add`. The file is
written to the `artifacts/` folder of the open project right away (the record on
the task is saved with the board), so a project must be open. Names are cleaned
to a plain file name and never overwrite an existing file (`notes.md` becomes
`notes-2.md`); only the accepted types are stored, their contents are checked
against the type, and the limits are 1 MiB for Markdown and SVG, 5 MiB for other
images and 50 artifacts per task. Request bodies up to 8 MiB are accepted, which
covers a base64-encoded 5 MiB image. Base64 costs output tokens (about 4/3 of
the file size), so agents should prefer text formats where they can.

Each artifact records who added it (`added_by`: `user` for files the user
attached from the task dialog, or the MCP client's name, for example
`claude-code`; `agent` over REST or when the client sent no name), when
(`added_at`) and the title of the task's column at that moment (`stage`, a
snapshot that renaming the column does not change). Task and artifact views
return all three; files attached by older versions may lack `added_by` and
`stage`. Agents cannot set these themselves.

Agents cannot replace or delete files. `artifact_detach` only removes the record
from the task; the file stays in `artifacts/` and the user decides what to do
with it. Task views list each artifact's `path` relative to the project folder,
and the Markdown export lists them under each task.

## Project instructions and the Claude Code skill

**Board ▸ Project Settings…** stores two texts in the board file: a document
generation prompt and code-authoring guidance. Agents read them with
`project_get`; they cannot change them.

**Agent ▸ Export Claude Code Skill…** writes a `SKILL.md` that explains the
board workflow and includes those instructions as they are right now. Save it as
`.claude/skills/stickynotes/SKILL.md` in a project (or
`~/.claude/skills/stickynotes/SKILL.md` for every project). Export again after
you change the settings; `project_get` always returns the current text.

## REST API

The same operations are available at `http://127.0.0.1:7317/api/v1` with the
same bearer token:

```
GET    /board                      GET  /project  (read-only)
GET    /export/markdown
GET    /tasks[?column=<id|title>]  POST /tasks
GET    /tasks/{id}                 PATCH /tasks/{id}      DELETE /tasks/{id}
POST   /tasks/{id}/advance         PUT  /tasks/{id}/criteria/{cid}  {"done": true}
POST   /tasks/{id}/artifacts       {"name": "a.md", "content": "..."}  or  {"name": "a.png", "content_base64": "..."}
GET    /tasks/{id}/artifacts/{id|name}      DELETE /tasks/{id}/artifacts/{id|name}  (detach)
```

Send `If-Match: <revision>` for optimistic concurrency (`409` on mismatch).
`403` means write access is off or the action is not allowed for agents; `409 no_project` means no project is open.
