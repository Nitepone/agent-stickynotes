# Connecting Claude Code

The app serves an MCP server over Streamable HTTP at `http://127.0.0.1:7317/mcp`
while its window is open. If port 7317 is busy, it uses a free port instead; the
**Agent ▸ Connect Claude Code…** dialog always shows the real address.

## 1. Register the server (once)

Open **Agent ▸ Connect Claude Code…** and click **Copy command**. It looks like:

```sh
claude mcp add --transport http --scope user stickynotes \
  http://127.0.0.1:7317/mcp --header "Authorization: Bearer <token>"
```

The token is generated on first launch and stored in
`~/.config/agent-stickynotes/token` (mode 0600). Every request needs it.

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
