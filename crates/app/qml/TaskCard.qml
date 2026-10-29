import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StickyNotes

// A sticky note. The root item is a placeholder that keeps the card's slot
// in the column; the visible note is reparented to `dragLayer` while dragged.
Item {
    id: root

    required property var task          // { id, number, cardText, done, total }
    required property Item dragLayer
    property bool dragEnabled: true
    readonly property bool isTaskCard: true
    readonly property bool dragging: mouse.drag.active

    signal clicked()

    objectName: "card-" + task.id
    implicitWidth: Theme.columnWidth - 20
    implicitHeight: note.height

    // Faint outline left behind while the note is being dragged.
    Rectangle {
        anchors.fill: parent
        radius: 4
        color: "transparent"
        border.color: Theme.subtleText
        border.width: 1
        opacity: 0.4
        visible: root.dragging
    }

    Item {
        id: note
        width: root.width
        height: Math.max(64, content.implicitHeight + 24)
        anchors.left: root.left
        anchors.top: root.top

        Drag.active: mouse.drag.active
        Drag.keys: ["task"]
        Drag.source: root

        Rectangle {
            x: 2; y: 3
            width: parent.width; height: parent.height
            radius: 4
            color: Theme.noteShadow
        }

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Theme.note
            border.color: mouse.containsMouse ? "#c9b85a" : "transparent"
        }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: root.task.cardText
                wrapMode: Text.Wrap
                color: Theme.noteText
                font.pixelSize: 14
            }

            // Footer: the task number at the bottom left, progress (if the
            // task has criteria) to its right.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                readonly property bool hasProgress: root.task.total > 0
                readonly property bool complete: hasProgress && root.task.done === root.task.total

                Label {
                    objectName: "cardNumber"
                    text: "#" + root.task.number
                    font.pixelSize: 11
                    color: Theme.noteNumber
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: parent.hasProgress
                    implicitHeight: 6
                    radius: 3
                    color: "#1f000000"

                    Rectangle {
                        width: parent.width * root.task.done / Math.max(1, root.task.total)
                        height: parent.height
                        radius: 3
                        color: parent.parent.complete ? Theme.progressDone : Theme.progress
                    }
                }

                Item { Layout.fillWidth: true; visible: !parent.hasProgress }

                Label {
                    visible: parent.hasProgress
                    text: "\u2713 " + root.task.done + "/" + root.task.total
                    font.pixelSize: 12
                    font.bold: true
                    color: parent.complete ? Theme.progressDone : Theme.subtleText
                }
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            drag.target: root.dragEnabled ? note : null
            drag.threshold: 6

            onPressed: (event) => {
                note.Drag.hotSpot.x = event.x
                note.Drag.hotSpot.y = event.y
            }
            onReleased: if (drag.active) note.Drag.drop()
            onClicked: root.clicked()
        }

        states: State {
            when: mouse.drag.active
            ParentChange { target: note; parent: root.dragLayer }
            AnchorChanges { target: note; anchors.left: undefined; anchors.top: undefined }
            PropertyChanges { note.rotation: 2; note.z: 100 }
        }
    }
}
