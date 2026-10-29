import QtQuick
import StickyNotes

// Underlines misspelled words in a text editor. Put it inside the editor:
//
//     TextArea { SpellUnderline { editor: parent; ranges: someFunction } }
//
// `ranges` is a function from the editor's text to `[[start, length], ...]`
// (UTF-16 positions, as the editor counts them); `null` turns the underlines
// off. The owner decides what is misspelled; this only draws it, shortly after
// typing or resizing stops.
Item {
    id: root

    required property var editor
    property var ranges: null

    // Underline segments to draw: [{ x, y, width }] in editor coordinates.
    property var spans: []

    anchors.fill: parent
    enabled: false      // never takes input

    function recompute() {
        if (typeof ranges !== "function" || !editor) {
            spans = []
            return
        }
        const found = ranges(editor.getText(0, editor.length))
        const result = []
        for (const [start, length] of found) {
            const from = editor.positionToRectangle(start)
            const to = editor.positionToRectangle(start + length)
            const y = from.y + from.height - 2
            if (Math.abs(to.y - from.y) < 2) {
                result.push({ x: from.x, y: y, width: Math.max(2, to.x - from.x) })
            } else {
                // The word wraps (it is longer than a line): underline its first line.
                result.push({ x: from.x, y: y, width: Math.max(2, editor.width - editor.rightPadding - from.x) })
            }
        }
        spans = result
    }

    onRangesChanged: recompute()
    Component.onCompleted: recompute()

    Timer {
        id: later
        interval: 250
        onTriggered: root.recompute()
    }

    Connections {
        target: root.editor
        function onTextChanged() { later.restart() }
        function onWidthChanged() { later.restart() }
        function onContentHeightChanged() { later.restart() }
    }

    Repeater {
        model: root.spans
        delegate: Rectangle {
            required property var modelData
            objectName: "spellUnderline"
            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: 2
            radius: 1
            color: Theme.danger
        }
    }
}
