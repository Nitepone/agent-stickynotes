import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// A sticky note. The root item is a placeholder that keeps the card's slot
// in the column; the visible note is reparented to `dragLayer` while dragged.
Item {
    id: root

    required property var task          // { id, number, cardText, done, total }
    required property Item dragLayer
    property bool dragEnabled: true
    // Set while an agent's change to this note has not been seen yet.
    property real glow: 0               // 0 to 1
    property bool glowEdited: false     // the agent edited its content
    property bool reducedMotion: false
    property bool glowActive: true      // false while scrolled out of view
    // Show the category as a label. Off for notes in a stack, whose header says it.
    property bool showCategory: true
    readonly property bool isTaskCard: true
    readonly property bool dragging: mouse.drag.active

    signal clicked()
    // Ctrl+Left / Ctrl+Right: ask for the note to move one column (-1 or +1).
    signal moveRequested(int direction)

    objectName: "card-" + task.id
    implicitWidth: Theme.columnWidth - 20
    implicitHeight: note.height

    // Keyboard and screen-reader access.
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: task.cardText
    Accessible.description: "#" + task.number
                            + (task.category ? ", " + qsTr("category %1").arg(task.category) : "")
                            + (task.total > 0 ? ", " + qsTr("%1 of %2 criteria done").arg(task.done).arg(task.total) : "")
    Accessible.focusable: true
    Accessible.onPressAction: root.clicked()

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true
            root.clicked()
        } else if ((event.modifiers & Qt.ControlModifier) && root.dragEnabled
                   && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            event.accepted = true
            root.moveRequested(event.key === Qt.Key_Right ? 1 : -1)
        }
    }

    // Focus ring, just outside the note (the column leaves room for it).
    Rectangle {
        objectName: "focusRing"
        anchors.fill: parent
        anchors.margins: -3
        radius: 7
        color: "transparent"
        border.color: Theme.focusRing
        border.width: 2
        visible: root.activeFocus
    }

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
            border.color: mouse.containsMouse ? Theme.noteHoverBorder : "transparent"
        }

        GlowEdge {
            objectName: "glowEdge"
            anchors.fill: parent
            intensity: root.glow
            edited: root.glowEdited
            reducedMotion: root.reducedMotion
            active: root.glowActive
            cornerRadius: 4
        }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10

            Rectangle {
                objectName: "cardCategory"
                visible: root.showCategory && !!root.task.category
                Layout.maximumWidth: content.width
                implicitWidth: categoryLabel.implicitWidth + 12
                implicitHeight: categoryLabel.implicitHeight + 4
                radius: 3
                color: Theme.noteChip

                Label {
                    id: categoryLabel
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, content.width - 12)
                    text: root.task.category || ""
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    font.bold: true
                    color: Theme.noteChipText
                }
            }

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

                Label {
                    objectName: "cardArtifacts"
                    visible: (root.task.artifactCount || 0) > 0
                    text: root.task.artifactCount === 1 ? qsTr("1 file") : qsTr("%1 files").arg(root.task.artifactCount)
                    font.pixelSize: 11
                    color: Theme.noteSubtleText
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: parent.hasProgress
                    implicitHeight: 6
                    radius: 3
                    color: Theme.progressTrack

                    Rectangle {
                        width: parent.width * root.task.done / Math.max(1, root.task.total)
                        height: parent.height
                        radius: 3
                        color: parent.parent.complete ? Theme.progressDone : Theme.primary
                    }
                }

                Item { Layout.fillWidth: true; visible: !parent.hasProgress }

                Label {
                    visible: parent.hasProgress
                    text: "\u2713 " + root.task.done + "/" + root.task.total
                    font.pixelSize: 12
                    font.bold: true
                    color: parent.complete ? Theme.noteDoneText : Theme.noteSubtleText
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
