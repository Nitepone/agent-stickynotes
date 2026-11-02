import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// The header row of a stack of same-category notes. One click, or Enter or
// Space when focused, collapses or expands the stack. The view keeps the state.
Item {
    id: root

    property string category: ""
    property string stackKey: ""
    property int count: 0
    property bool collapsed: false
    property bool reducedMotion: false
    readonly property bool isStackHeader: true

    signal toggled()

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
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
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
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
