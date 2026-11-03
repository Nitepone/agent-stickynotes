import QtQuick
import QtQuick.Controls.Fusion
import StickyNotes

// Multi-line text input with a visible frame (Fusion's TextArea has none).
TextArea {
    id: area

    // Underlines misspelled words: a function from the text to
    // `[[start, length], ...]` (see SpellUnderline), or null for none.
    property var spellRanges: null
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

    SpellUnderline {
        editor: area
        ranges: area.spellRanges
    }
}
