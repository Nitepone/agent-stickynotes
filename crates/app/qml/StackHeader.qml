import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// The header row of a stack of same-category notes. One click, or Enter or
// Space when focused, collapses or expands the stack. The view keeps the state.
// Dragging the header moves the whole stack (`taskIds`, in stored order): like
// TaskCard, the root keeps the slot and the visible face is reparented to
// `dragLayer` while dragged. Ctrl+Left / Ctrl+Right move it one column.
Item {
    id: root

    property string category: ""
    property string stackKey: ""
    property int count: 0
    property bool collapsed: false
    property bool reducedMotion: false
    property var taskIds: []
    property Item dragLayer: null
    property bool dragEnabled: true
    readonly property bool isStackHeader: true
    readonly property bool dragging: mouse.drag.active && !cancelled
    // Escape during a drag abandons it; the release then does nothing.
    property bool cancelled: false

    signal toggled()
    // Ctrl+Left / Ctrl+Right: ask for the whole stack to move one column (-1 or +1).
    signal moveRequested(int direction)

    objectName: "stackHeader-" + category.toLowerCase()
    implicitWidth: Theme.columnWidth - 20
    implicitHeight: 32

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: qsTr("%1, %2 tasks").arg(category).arg(count)
    Accessible.description: collapsed ? qsTr("Collapsed. Press to expand.") : qsTr("Expanded. Press to collapse.")
    Accessible.focusable: true
    Accessible.onPressAction: root.toggled()

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape && mouse.drag.active) {
            event.accepted = true
            root.cancelled = true
        } else if ((event.modifiers & Qt.ControlModifier) && root.dragEnabled
                   && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
            event.accepted = true
            root.moveRequested(event.key === Qt.Key_Right ? 1 : -1)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true
            root.toggled()
        }
    }

    Rectangle {
        objectName: "focusRing"
        anchors.fill: parent
        anchors.margins: -3
        radius: 8
        color: "transparent"
        border.color: Theme.focusRing
        border.width: 2
        visible: root.activeFocus
    }

    Item {
        id: face
        width: root.width
        height: root.height
        anchors.left: root.left
        anchors.top: root.top

        Drag.active: mouse.drag.active && !root.cancelled
        Drag.keys: ["stack"]
        Drag.source: root

        Rectangle {
            anchors.fill: parent
            radius: 5
            color: Theme.stackHeaderBackground
            border.color: mouse.containsMouse ? Theme.subtleText : "transparent"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Label {
                objectName: "stackChevron"
                text: "▸"      // right-pointing; rotated down when expanded
                font.pixelSize: 13
                color: Theme.text
                rotation: root.collapsed ? 0 : 90
                Behavior on rotation {
                    enabled: !root.reducedMotion
                    NumberAnimation { duration: 120 }
                }
            }

            Label {
                objectName: "stackName"
                Layout.fillWidth: true
                text: root.category
                font.pixelSize: 13
                font.bold: true
                color: Theme.text
                elide: Text.ElideRight
            }

            Label {
                objectName: "stackCount"
                text: root.count
                font.pixelSize: 12
                font.bold: true
                color: Theme.stackHeaderCount
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            drag.target: root.dragEnabled && !root.cancelled ? face : null
            drag.threshold: 6

            onPressed: (event) => {
                root.cancelled = false
                root.forceActiveFocus()
                face.Drag.hotSpot.x = event.x
                face.Drag.hotSpot.y = event.y
            }
            onReleased: if (drag.active && !root.cancelled) face.Drag.drop()
            onClicked: root.toggled()
        }

        states: State {
            when: root.dragging
            ParentChange { target: face; parent: root.dragLayer }
            AnchorChanges { target: face; anchors.left: undefined; anchors.top: undefined }
            PropertyChanges { face.rotation: 2; face.z: 100 }
        }
    }
}
