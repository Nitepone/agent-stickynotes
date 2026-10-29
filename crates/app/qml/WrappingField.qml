import QtQuick
import QtQuick.Controls
import StickyNotes

// A single list item (requirement, criterion) that wraps onto extra lines and
// grows in height as needed. Unlike a TextField it never scrolls sideways;
// unlike a plain TextArea it never contains a line break: Enter is ignored
// and pasted newlines become spaces.
FormTextArea {
    id: field

    selectByMouse: true

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            event.accepted = true
    }

    onTextChanged: {
        if (text.indexOf("\n") < 0)
            return
        const pos = cursorPosition
        text = text.replace(/\s*\n\s*/g, " ")
        cursorPosition = Math.min(pos, text.length)
    }
}
