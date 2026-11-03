import QtQuick
import QtQuick.Controls.Fusion
import StickyNotes

// Drop target for deleting tasks. Emits `taskDropped`; the caller confirms.
Rectangle {
    id: root

    property bool dragInProgress: false
    readonly property bool hot: drop.containsDrag

    signal taskDropped(string taskId)

    implicitWidth: Theme.px(48)
    implicitHeight: Theme.px(48)
    radius: width / 2
    color: hot ? Theme.danger : Theme.fieldBackground
    border.color: Theme.danger
    border.width: 2
    opacity: hot || dragInProgress ? 1.0 : 0.55
    scale: hot ? 1.15 : 1.0
    Behavior on scale { NumberAnimation { duration: 120 } }

    readonly property color ink: hot ? Theme.textOnDanger : Theme.danger

    // Simple trash-can glyph.
    Item {
        anchors.centerIn: parent
        width: 30
        height: 34
        scale: 0.7 * Theme.scale   // drawn on a fixed 30 x 34 grid

        Rectangle { x: 10; y: 0; width: 10; height: 4; radius: 1; color: root.ink }
        Rectangle { x: 0; y: 4; width: 30; height: 4; radius: 1; color: root.ink }
        Rectangle {
            x: 3; y: 10; width: 24; height: 24; radius: 3
            color: "transparent"
            border.color: root.ink
            border.width: 3
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    x: 7 + index * 7; y: 5; width: 3; height: 14; radius: 1
                    color: root.ink
                }
            }
        }
    }

    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered
    ToolTip.text: qsTr("Drag a task here to delete it")

    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["task"]
        onDropped: (event) => {
            event.accept()
            root.taskDropped(event.source.task.id)
        }
    }
}
