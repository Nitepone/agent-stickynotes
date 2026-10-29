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
**Agent ▸ Allow Agent Write Access** (or click the grey *Agent: read-only*
pill). The setting is remembered. While it is off, write tools return an
error that tells the agent to ask you.

## What the agent can do

| Tool | Purpose |
|---|---|
| `board_get` | Columns in order (with their entry criteria), task summaries, revision, write flag |
| `task_list` | Task summaries, optionally for one column (id or title) |
| `task_get` | Full task plus `next_column` (where `task_advance` would move it, with its criteria) |
| `task_create` | New task; always lands in the first column |
| `task_update` | Change description, extended description, requirements, criteria, and `references` (links to other tasks: `blocks`, `blocked_by`, `relates_to`, `duplicates`, `duplicated_by`; the other task gets the mirrored relation) |
| `task_advance` | Move one column to the right; the agent must check `next_column.description` first |
| `task_delete` | Delete a task |
| `criterion_set` | Tick or untick an acceptance criterion |

Resources: `stickynotes://board` (JSON) and `stickynotes://board.md` (Markdown).

Agents cannot move tasks backwards, skip columns, or change columns at all;
the core enforces this. All write tools accept `expected_revision`, and a
mismatch means the board changed and the agent should re-read it.

Agent edits appear in the window immediately and count as unsaved changes.
Save the board to keep them.

## REST API

The same operations are available at `http://127.0.0.1:7317/api/v1` with the
same bearer token:

```
GET    /board                      GET  /export/markdown
GET    /tasks[?column=<id|title>]  POST /tasks
GET    /tasks/{id}                 PATCH /tasks/{id}      DELETE /tasks/{id}
POST   /tasks/{id}/advance         PUT  /tasks/{id}/criteria/{cid}  {"done": true}
```

Send `If-Match: <revision>` for optimistic concurrency (`409` on mismatch).
`403` means write access is off or the action is not allowed for agents.
