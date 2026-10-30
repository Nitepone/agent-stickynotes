# Development

```sh
cargo test --workspace          # core, API and MCP tests
./scripts/qml-tests.sh          # QML view tests (headless, real mouse drags)
cargo clippy --workspace --all-targets -- -D warnings
cargo test -p stickynotes real_claude -- --ignored   # optional: one real Claude Code call
```

Headless screenshots for UI checks:
`STICKYNOTES_SCREENSHOT=out.png[:scene[:delayMs[:WxH]]] QT_QPA_PLATFORM=offscreen cargo run -- <project-folder>`,
where `scene` is `board`, `artifacts`, `edit`, `task`, `newtask`, `column`, `agent`, `project`, `prefs`, `editor`, `note-demo`, `theme-demo`, `theme-reset`, `interact`, `synthetic` or `generate`.

## Layout

| Crate | Role |
|---|---|
| `crates/core` | **Model.** Board types, commands, agent rules, `BoardStore` (single write path, revision, dirty flag, change events), JSON persistence, Markdown export. No UI or network code. |
| `crates/server` | **Agent controllers.** `AgentService` plus thin REST (`/api/v1`) and MCP (`/mcp`, Streamable HTTP via `rmcp`) transports, bearer-token auth. |
| `crates/app` | **UI.** `BoardController` (CXX-Qt) turns view intents into commands and republishes store state. `viewmodel.rs` shapes data for QML. `qml/` holds the views. Only `Main.qml` talks to the controller. |

See [PLAN.md](../PLAN.md) for the design and milestone status.
