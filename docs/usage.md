# Using the app

| Action | How |
|---|---|
| Add a task | **+** at the bottom of a column |
| Edit a task | Click the sticky note |
| Refer to a task | Every task has a permanent number (`#12`) at the bottom left of the note and in its dialog. Numbers are never reused. Tell an agent "look at #12"; every agent tool accepts `#12` in place of an id. |
| Move a task | Drag the note to a position in any column |
| Delete a task | Drag it onto the trash can (bottom right), or **Delete** in its dialog |
| Draft requirements and criteria | In a task's dialog, **Draft requirements & criteria**. Claude Code (or an Ollama server, see Preferences ▸ Editor) proposes new items from the descriptions; it also picks one of the board's existing categories if the task has none (a note appears if it cannot). Review the result, then **Save**. **Undo draft** (next to the button, after confirming) puts the requirements, criteria and category back as they were before the draft. Claude Code needs `claude` on your PATH. |
| Link tasks | In a task's dialog, **References**: pick a relation and a task, **Add**, then **Save**. The other task shows the matching reverse link. |
| Group tasks | In a task's dialog, **Category**: pick one already on the board or type a new name (case is ignored: "ui" selects "UI"), and use the clear button to remove it. Tasks of one category in the same column stack under a header showing the name and count; click it (or press Enter/Space) to collapse or expand the stack. Uncategorized tasks and a lone categorized task stay ordinary cards. Collapsed state is not saved. |
| Open an artifact | Click a file in a task's dialog (or in **Board ▸ Project Settings…**, which lists every file in `artifacts/`). It opens in its own window: Markdown has a contents pane to jump between sections, search (Ctrl+F; Enter / Shift+Enter for next and previous), zoom (Ctrl+`+`/`-`/`0` or Ctrl + wheel) and a display style menu (Default, Reading, Compact, Monospace) that is remembered; images fit the window or show at actual size. |
| Attach a file | In an existing task's dialog, **Artifacts ▸ Attach file…** picks a Markdown or image file (same types and size limits as for agents). A copy goes into `artifacts/` (renamed if the name is taken) and is attached at once, as a change you can undo; the original is untouched and an undo leaves the copy in `artifacts/`. Each attached file shows who added it (You, the agent's name, or "added by an agent" on older files), when, and the column the task was in at that moment. Errors (wrong type, too big, unreadable) appear under the button and nothing is attached. |
| Attach by drag and drop or paste | In an existing task's dialog, drop one or more files from a file manager anywhere on the dialog (it is outlined while you drag) to attach them, or press **Ctrl+V** while no text field has the keyboard: a copied image (such as a screenshot) is saved as `pasted-YYYYMMDD-HHMMSS.png`, and copied files are attached like dropped ones. In a text field Ctrl+V pastes text as usual, and copied text alone is not attached. Each file is checked on its own with the same rules as the button: good ones attach, and refused ones are listed with name and reason under the Artifacts section. In the New Task dialog nothing is attached; save the task first. |
| See every artifact | The folder icon in the toolbar (left of the gear) lists all files in `artifacts/`, newest first, under Today / This week (last 7 days) / This month (last 30 days) / Earlier. Each row has the file's icon, name, a `#12` pill for every task it is attached to (click to open the task) and its date; click the row to open the file. |
| Give agents project instructions | **Board ▸ Project Settings…** (document prompt, code guidance); **Agent ▸ Export Claude Code Skill…** writes them into a `SKILL.md` |
| See what an agent changed | Notes an agent created, moved, edited or ticked criteria on **glow green** at the edges (a highlight circles the note; an edited note also gets a sheen). The glow stays until you are back, then fades over 20 seconds. Your own changes never glow. With reduced motion (Preferences ▸ Personalization ▸ Motion, or the desktop's setting) the glow is still. |
| Review what agents did over time | **Agent ▸ Activity…** lists, for each day, a summary line (for example "Today: 12 changes by claude-code on 5 tasks: 2 created, 3 advanced, 4 criteria ticked") and then that day's changes, newest first ("10:42 claude-code advanced #12 to Review"). It is read from `activity.jsonl` in the project folder (see [claude-code-setup.md](claude-code-setup.md#activity-log)). Your own changes are not listed. |
| Change the look | **File ▸ Preferences…** (Ctrl+,) or the gear icon in the toolbar: Personalization has Light/Dark, primary and secondary accent colors and the sticky note color (presets, a hex code, or a picker), plus resets. **Note style** is either *User color* (one color for every note, the default) or *Variable*: pick a palette (Pastel, Soft earth, Candy, Cool) and each category gets its own color from it, assigned alphabetically (case ignored), so the same categories always get the same colors whatever order they were created in; with more categories than palette colors the colors repeat, and uncategorized notes keep your note color. Text on a note adjusts to stay readable on any color. **Show bottom bar** (on by default) controls the strip at the bottom with the hint and the trash can; turn it off to give the board the extra height. With the bar hidden, a trash can appears in the bottom-right corner while you drag a task (not while editing columns); drop the task on it to delete it, with the same confirmation, and it disappears when the drag ends. Changes apply immediately and are remembered. |
| Make everything bigger or smaller | **View ▸ Zoom In / Zoom Out / Actual Size** (the menu shows the current percentage), or Ctrl+`=` (also Ctrl+`+`) to zoom in, Ctrl+`-` to zoom out and Ctrl+`0` for actual size. It scales text, cards, columns, dialogs, icons and the minimum window size in steps of 10% from 70% to 200%, applies immediately and is remembered. While an artifact window is open, those keys zoom only its document (the document zoom is on top of the app scale). |
| Spell check and the draft agent | Preferences ▸ Editor: turn the red underlines for misspelled words in the task editor on or off, and choose how the draft agent runs (agent type, an extra system prompt, and for Claude Code the model and thinking level, or for an Ollama server its endpoint, model and optional auth token; **Test connection** next to the endpoint checks the saved endpoint and token without drafting anything). |
| Edit a column | Click the column title |
| Reorder / add / delete columns | the pencil icon (toolbar) or **Board ▸ Edit Columns** |
| Save / open / new | **File ▸ New Project… / Open Project…** (the picker), **File ▸ Save**. A floppy-disk icon appears in the toolbar while there are unsaved changes. You are warned before unsaved changes are lost. |

## Spell check

The task editor underlines misspelled words using a Hunspell dictionary
(`.aff` + `.dic`) for your language (from `LANG`), or American English. It looks
in `/usr/share/hunspell`, `/usr/share/myspell`, Homebrew's and macOS's spelling
folders, a `dictionaries` folder next to the executable (the AppImage ships
`en_US` there), and `$STICKYNOTES_DICT_DIR`. With no dictionary nothing is
underlined, and Preferences ▸ Editor says so. Acronyms, `camelCase`, words with
digits and paths or addresses are not flagged.

## Drafting (Claude Code or an Ollama-style server)

The draft button runs `claude -p` as a subprocess, with no tools, MCP servers or
session history, and sends it a system prompt plus the task as JSON (the
project's document and code guidance are included as context). Nothing is
saved until you click **Save**, existing items are kept, and a draft can be
cancelled. Preferences ▸ Editor adds your own system prompt to the built-in one
(which fixes the reply format) and sets Claude Code's `--model` and `--effort`.
If `claude` is not on your PATH, set `"claude_command"` in
`~/.config/agent-stickynotes/settings.json`. The backend sits behind the
`DraftBackend` trait (`crates/app/src/drafting.rs`).

Choose **Ollama server** as the agent type in Preferences ▸ Editor to draft with
a model served over HTTP instead. Set the endpoint (default
`http://localhost:11434`), the model name (required, e.g. `llama3.2`) and, if the
server wants one, an auth token (masked in the field, sent as
`Authorization: Bearer <token>` only when set, and stored in plain text in
`settings.json`; it is never logged). The app sends one non-streaming
`POST <endpoint>/v1/chat/completions` asking for a JSON reply, the same
OpenAI-compatible call that both Ollama and llama.cpp's `llama-server` answer, so
either can be used (for llama.cpp, point the endpoint at `llama-server`, e.g.
`http://localhost:8080`, and use any model name; start it with `--api-key` to
require a token). The HTTP client is `ureq`, a small blocking client; the `ollama-rs`
crate was not used because it targets Ollama's native API, which would need a
second code path for llama.cpp. An unreachable server shows `Cannot reach the Ollama
server at <endpoint>`, and a 401/403 shows that the server rejected the auth token.
The same system prompt and reply parsing as for Claude Code apply.


## Backups and restore

Every save keeps the file it replaces, so a bad edit or a bad agent run is not final.

- `stickynotes.json.bak` next to the board is the file as it was before the last save (there is none after the very first save).
- `backups/` in the project holds timestamped snapshots (`board-YYYYMMDD-HHMMSS.json`) of the file on disk before a save: at most one every 10 minutes, and always on the first save after opening a project. The newest 20 are kept; older ones are deleted. The folder is created when needed.
- If a backup cannot be made (a read-only folder, say), the save still succeeds and you get one message about it per opened project.

**Board > Restore from Backup...** lists the `.bak` and the snapshots, newest first, with the time and the number of tasks. A file that cannot be read as a board is shown as unreadable and cannot be chosen. After you confirm, the current file is first snapshotted, then the chosen backup becomes the open board. It stays **unsaved** until you save, so you can still look at it and walk away, and undo history is cleared.
