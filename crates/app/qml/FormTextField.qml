import QtQuick
import QtQuick.Controls.Fusion
import StickyNotes

// Single-line text input with a visible frame, like FormTextArea.
TextField {
    id: field

    property bool invalid: false

    selectByMouse: true
    onTextEdited: invalid = false
    background: Rectangle {
        radius: Theme.px(3)
        color: Theme.fieldBackground
        border.color: field.invalid ? Theme.danger
                      : field.activeFocus ? Theme.primary : Theme.fieldBorder
    }
}
