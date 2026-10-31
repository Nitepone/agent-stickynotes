import QtQuick

// Keeps one axis of a Flickable steady across a board refresh. Rebuilding the
// cards grows the content gradually, so restore() applies the wanted offset
// again whenever the content size changes for a short while.
Item {
    id: root

    required property Flickable flickable
    property bool horizontal: false

    property real wanted: 0
    property bool restoring: false

    function maxOffset() {
        return horizontal ? Math.max(0, flickable.contentWidth - flickable.width)
                          : Math.max(0, flickable.contentHeight - flickable.height)
    }

    function apply(v) {
        const clamped = Math.min(v, maxOffset())
        if (horizontal)
            flickable.contentX = clamped
        else
            flickable.contentY = clamped
    }

    // Scroll to `v`, clamped to the content.
    function restore(v) {
        wanted = v
        restoring = v > 0
        apply(v)
        if (restoring)
            timer.restart()
    }

    Timer {
        id: timer
        interval: 150
        onTriggered: root.restoring = false
    }
    Connections {
        target: root.flickable
        function onContentWidthChanged() {
            if (root.restoring && root.horizontal)
                root.apply(root.wanted)
        }
        function onContentHeightChanged() {
            if (root.restoring && !root.horizontal)
                root.apply(root.wanted)
        }
    }
}
