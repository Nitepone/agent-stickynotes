import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Read-only monospace text with a copy button, for commands and config snippets.
ColumnLayout {
    id: root

    property string text: ""
    property string copyLabel: qsTr("Copy")
    readonly property alias area: area
    readonly property bool copied: copiedLabel.visible

    Layout.fillWidth: true
    spacing: 4

    TextArea {
        id: area
        Layout.fillWidth: true
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        font.family: "monospace"
        text: root.text
        Accessible.name: root.copyLabel
    }
    RowLayout {
        Button {
            objectName: "copyButton"
            text: root.copyLabel
            onClicked: {
                area.selectAll()
                area.copy()
                area.deselect()
                copiedLabel.visible = true
            }
        }
        Label { id: copiedLabel; visible: false; text: qsTr("Copied"); color: Theme.success }
    }
    onTextChanged: copiedLabel.visible = false
    function reset() { copiedLabel.visible = false }
}
