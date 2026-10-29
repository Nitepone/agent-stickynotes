import QtQuick
import QtQuick.Controls
import StickyNotes

// Multi-line text input with a visible frame (Fusion's TextArea has none).
TextArea {
    id: area
    wrapMode: TextEdit.Wrap
    leftPadding: 8
    rightPadding: 8
    topPadding: 6
    bottomPadding: 6
    background: Rectangle {
        color: "white"
        radius: 3
        border.color: area.activeFocus ? Theme.dropIndicator : "#b8bec8"
    }
}
