import QtQuick
import QtQuick.Controls.Fusion
import StickyNotes

// The interface zoom commands: Ctrl+= (or Ctrl++) zooms in, Ctrl+- out and
// Ctrl+0 returns to actual size. This only asks for a new scale
// (`scaleRequested`); the owner stores it and passes it back as `current`.
// Set `active` to false while something else owns these keys (the artifact
// viewer's own document zoom): two enabled shortcuts on one key fire neither.
Item {
    id: root

    property real current: 1.0
    property bool active: true
    signal scaleRequested(real value)

    readonly property int percent: Math.round(current * 100)
    readonly property alias zoomInAction: zoomIn
    readonly property alias zoomOutAction: zoomOut
    readonly property alias actualSizeAction: actualSize

    Action {
        id: zoomIn
        text: qsTr("Zoom &In")
        shortcut: "Ctrl+="
        enabled: root.active && root.current < Theme.maxScale - 0.001
        onTriggered: root.scaleRequested(Theme.steppedScale(root.current, 1))
    }
    // What the keyboard sends for Ctrl and the plus key (Shift is part of it).
    Shortcut {
        sequences: [StandardKey.ZoomIn]
        enabled: zoomIn.enabled
        onActivated: zoomIn.trigger()
    }
    Action {
        id: zoomOut
        text: qsTr("Zoom &Out")
        shortcut: "Ctrl+-"
        enabled: root.active && root.current > Theme.minScale + 0.001
        onTriggered: root.scaleRequested(Theme.steppedScale(root.current, -1))
    }
    Action {
        id: actualSize
        text: qsTr("&Actual Size (%1%)").arg(root.percent)
        shortcut: "Ctrl+0"
        enabled: root.active && root.percent !== 100
        onTriggered: root.scaleRequested(1)
    }
}
