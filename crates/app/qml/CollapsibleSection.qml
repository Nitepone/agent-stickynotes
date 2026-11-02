import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// A titled section that expands and collapses on its own. The header takes Tab
// focus, toggles on click, Enter or Space, and is exposed as a button with its
// expanded state. Children go inside and show only while expanded.
Item {
    id: root

    property string title: ""
    property bool expanded: false
    property bool reducedMotion: false
    default property alias content: body.data

    readonly property alias header: header

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight
    Layout.fillWidth: true

    function toggle() { expanded = !expanded }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        Item {
            id: header
            objectName: "sectionHeader"
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + 8
            activeFocusOnTab: true

            Accessible.role: Accessible.Button
            Accessible.name: root.title
            Accessible.description: root.expanded ? qsTr("Expanded") : qsTr("Collapsed")
            Accessible.focusable: true
            Accessible.onPressAction: root.toggle()

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    event.accepted = true
                    root.toggle()
                }
            }

            RowLayout {
                id: headerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Label {
                    id: chevron
                    objectName: "chevron"
                    text: "▸"
                    color: Theme.subtleText
                    rotation: root.expanded ? 90 : 0
                    Behavior on rotation {
                        enabled: !root.reducedMotion
                        NumberAnimation { duration: 120 }
                    }
                }
                Label {
                    text: root.title
                    font.bold: true
                    color: Theme.text
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                objectName: "focusRing"
                anchors.fill: parent
                radius: 4
                color: "transparent"
                border.color: Theme.focusRing
                border.width: 2
                visible: header.activeFocus
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { header.forceActiveFocus(); root.toggle() }
            }
        }

        ColumnLayout {
            id: body
            objectName: "sectionBody"
            Layout.fillWidth: true
            Layout.leftMargin: 20
            visible: root.expanded
            spacing: 8
        }
    }
}
