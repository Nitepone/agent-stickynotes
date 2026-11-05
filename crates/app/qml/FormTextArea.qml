import QtQuick
import QtQuick.Controls.Fusion
import StickyNotes

// Multi-line text input with a visible frame (Fusion's TextArea has none), and
// a right-click menu (SpellMenu) with spelling suggestions and Cut/Copy/Paste.
TextArea {
    id: area

    // Underlines misspelled words: a function from the text to
    // `[[start, length], ...]` (see SpellUnderline), or null for none.
    property var spellRanges: null
    // Replacements for one misspelled word: a function from the word to a
    // list of strings, or null for no suggestions in the menu.
    property var spellSuggestions: null
    property alias contextMenu: menu

    wrapMode: TextEdit.Wrap
    leftPadding: Theme.px(8)
    rightPadding: Theme.px(8)
    topPadding: Theme.px(6)
    bottomPadding: Theme.px(6)
    background: Rectangle {
        color: Theme.fieldBackground
        radius: Theme.px(3)
        border.color: area.activeFocus ? Theme.primary : Theme.fieldBorder
    }

    Keys.onPressed: (event) => {
        if (menu.handleKey(event)) {
            event.accepted = true
        } else if (event.key === Qt.Key_Menu
                   || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            menu.openAtCursor()
            event.accepted = true
        }
    }

    SpellUnderline {
        editor: area
        ranges: area.spellRanges
    }

    // Right button only: left clicks, drags and the wheel reach the editor.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.IBeamCursor
        onPressed: (mouse) => {
            area.forceActiveFocus()
            menu.openAtPoint(mouse.x, mouse.y)
        }
    }

    SpellMenu {
        id: menu
        editor: area
        ranges: area.spellRanges
        suggest: area.spellSuggestions
    }
}
