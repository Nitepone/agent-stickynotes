# Using the app

| Action | How |
|---|---|
| Add a task | **+** at the bottom of a column |
| Edit a task | Click the sticky note |
| Refer to a task | Every task has a permanent number (`#12`) at the bottom left of the note and in its dialog. Numbers are never reused. Tell an agent "look at #12"; every agent tool accepts `#12` in place of an id. |
| Move a task | Drag the note to a position in any column |
| Delete a task | Drag it onto the trash can (bottom right), or **Delete** in its dialog |
| Draft requirements and criteria | In a task's dialog, **Draft requirements & criteria**. Claude Code proposes new items from the descriptions; it also picks one of the board's existing categories if the task has none (a note appears if it cannot). Review the result, then **Save**. **Undo draft** (next to the button, after confirming) puts the requirements, criteria and category back as they were before the draft. Needs `claude` on your PATH. |
| Link tasks | In a task's dialog, **References**: pick a relation and a task, **Add**, then **Save**. The other task shows the matching reverse link. |
| Group tasks | In a task's dialog, **Category**: pick one already on the board or type a new name (case is ignored: "ui" selects "UI"), and use the clear button to remove it. Tasks of one category in the same column stack under a header showing the name and count; click it (or press Enter/Space) to collapse or expand the stack. Uncategorized tasks and a lone categorized task stay ordinary cards. Collapsed state is not saved. |
| Open an artifact | Click a file in a task's dialog (or in **Board ▸ Project Settings…**, which lists every file in `artifacts/`). It opens in its own window: Markdown has a contents pane to jump between sections, search (Ctrl+F; Enter / Shift+Enter for next and previous), zoom (Ctrl+`+`/`-`/`0` or Ctrl + wheel) and a display style menu (Default, Reading, Compact, Monospace) that is remembered; images fit the window or show at actual size. |
| See every artifact | The folder icon in the toolbar (left of the gear) lists all files in `artifacts/`, newest first, under Today / This week (last 7 days) / This month (last 30 days) / Earlier. Each row has the file's icon, name, a `#12` pill for every task it is attached to (click to open the task) and its date; click the row to open the file. |
| Give agents project instructions | **Board ▸ Project Settings…** (document prompt, code guidance); **Agent ▸ Export Claude Code Skill…** writes them into a `SKILL.md` |
| See what an agent changed | Notes an agent created, moved, edited or ticked criteria on **glow green** at the edges (a highlight circles the note; an edited note also gets a sheen). The glow stays until you are back, then fades over 20 seconds. Your own changes never glow. With reduced motion (Preferences ▸ Personalization ▸ Motion, or the desktop's setting) the glow is still. |
| Change the look | **File ▸ Preferences…** (Ctrl+,) or the gear icon in the toolbar: Personalization has Light/Dark, primary and secondary accent colors and the sticky note color (presets, a hex code, or a picker), plus resets. Text on a note adjusts to stay readable on any color. Changes apply immediately and are remembered. |
| Spell check and the draft agent | Preferences ▸ Editor: turn the red underlines for misspelled words in the task editor on or off, and choose how the draft agent runs (agent type, an extra system prompt, and for Claude Code the model and thinking level). |
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

## Drafting with Claude Code

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

