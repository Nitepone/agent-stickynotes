import QtQuick
import QtQuick.Controls.Fusion
import StickyNotes

// The right-click menu of a text field: replacements for the misspelled word
// under the pointer (while spell check is on), then Cut, Copy, Paste and
// Select All. Put it inside the editor and call `openAtPoint` on a right click
// and `openAtCursor` for the Menu key or Shift+F10; pass key presses to
// `handleKey` so one Ctrl+Z undoes a replacement.
//
// `ranges` finds misspelled words (see SpellUnderline) and `suggest` returns
// replacements for one word; with either null there are no spelling items.
Menu {
    id: menu

    required property var editor
    property var ranges: null
    property var suggest: null

    // The misspelled word the menu was opened on, { start, end, word }, or null.
    property var target: null
    property var suggestions: []
    readonly property bool spelling: target !== null
    readonly property int maxSuggestions: 5
    // The selection when the menu opened; opening the menu can clear it.
    property int selStart: 0
    property int selEnd: 0
    // The last replacement: TextEdit records it as a removal and an insertion,
    // so `handleKey` turns one Ctrl+Z (or redo) into two.
    property var lastReplacement: null

    function textNow() { return editor.getText(0, editor.length) }

    function misspelledAt(pos) {
        if (typeof ranges !== "function" || typeof suggest !== "function")
            return null
        const text = textNow()
        for (const [start, length] of ranges(text)) {
            if (pos >= start && pos <= start + length)
                return { start: start, end: start + length, word: text.substr(start, length) }
        }
        return null
    }

    function openAt(x, y, pos) {
        selStart = editor.selectionStart
        selEnd = editor.selectionEnd
        target = misspelledAt(pos)
        suggestions = target ? (suggest(target.word) || []).slice(0, maxSuggestions) : []
        rebuildSpellingItems()
        popup(x, y)
    }

    // A right click at (x, y) in the editor. Like other editors, the cursor
    // moves to the click unless it falls inside the selection.
    function openAtPoint(x, y) {
        const pos = editor.positionAt(x, y)
        if (editor.selectedText === "" || pos < editor.selectionStart || pos > editor.selectionEnd)
            editor.cursorPosition = pos
        openAt(x, y, pos)
    }

    function openAtCursor() {
        const r = editor.cursorRectangle
        openAt(r.x, r.y + r.height, editor.cursorPosition)
    }

    function replace(word) {
        const t = target
        if (!t || editor.readOnly)
            return
        const before = textNow()
        editor.remove(t.start, t.end)
        editor.insert(t.start, word)
        editor.cursorPosition = t.start + word.length
        lastReplacement = { before: before, after: textNow(), undone: false }
    }

    // A key press in the editor; true when it was handled here.
    function handleKey(event) {
        const r = lastReplacement
        if (!r)
            return false
        if (event.matches(StandardKey.Undo) && !r.undone && textNow() === r.after) {
            editor.undo()
            editor.undo()
            r.undone = true
            return true
        }
        if (event.matches(StandardKey.Redo) && r.undone && textNow() === r.before) {
            editor.redo()
            editor.redo()
            r.undone = false
            return true
        }
        return false
    }

    // The spelling part of the menu is made fresh on each opening, so the
    // menu only ever holds the items that apply to the word clicked.
    property var spellingItems: []
    readonly property Component suggestionItem: Component {
        MenuItem {
            objectName: "spellSuggestion"
            font.bold: true
            onTriggered: menu.replace(text)
        }
    }
    readonly property Component noSuggestionsItem: Component {
        MenuItem {
            objectName: "noSuggestions"
            enabled: false
            text: qsTr("No suggestions")
        }
    }
    readonly property Component separatorItem: Component { MenuSeparator {} }

    function rebuildSpellingItems() {
        for (const item of spellingItems)
            removeItem(item)
        const made = []
        if (spelling) {
            if (suggestions.length === 0)
                made.push(noSuggestionsItem.createObject(null))
            for (const word of suggestions)
                made.push(suggestionItem.createObject(null, { text: word }))
            made.push(separatorItem.createObject(null))
        }
        made.forEach((item, i) => insertItem(i, item))
        spellingItems = made
    }

    function restoreSelection() {
        if (selEnd > selStart)
            editor.select(selStart, selEnd)
    }

    onClosed: editor.forceActiveFocus()

    MenuItem {
        objectName: "cutItem"
        text: qsTr("Cut")
        enabled: !menu.editor.readOnly && menu.selEnd > menu.selStart
        onTriggered: { menu.restoreSelection(); menu.editor.cut() }
    }
    MenuItem {
        objectName: "copyItem"
        text: qsTr("Copy")
        enabled: menu.selEnd > menu.selStart
        onTriggered: { menu.restoreSelection(); menu.editor.copy() }
    }
    MenuItem {
        objectName: "pasteItem"
        text: qsTr("Paste")
        enabled: !menu.editor.readOnly && menu.editor.canPaste
        onTriggered: { menu.restoreSelection(); menu.editor.paste() }
    }
    MenuItem {
        objectName: "selectAllItem"
        text: qsTr("Select All")
        enabled: menu.editor.length > 0
        onTriggered: menu.editor.selectAll()
    }
}
