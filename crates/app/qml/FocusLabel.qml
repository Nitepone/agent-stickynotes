import QtQuick
import QtQuick.Controls.Fusion
import StickyNotes

// A text that acts as a button (board title, column title): takes Tab focus,
// activates on Enter or Space, and is exposed to screen readers as a button.
Item {
    id: root

    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    property alias elide: label.elide
    property string accessibleName: text
    readonly property alias containsMouse: mouse.containsMouse

    signal clicked()

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.focusable: true
    Accessible.onPressAction: root.clicked()

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true
            root.clicked()
        }
    }

    Label {
        id: label
        anchors.fill: parent
        color: Theme.text
    }

    Rectangle {
        objectName: "focusRing"
        anchors.fill: parent
        anchors.margins: -3
        radius: 4
        color: "transparent"
        border.color: Theme.focusRing
        border.width: 2
        visible: root.activeFocus
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
