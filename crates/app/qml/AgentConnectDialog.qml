import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// How to register the board's MCP server with Claude Code. The owner supplies
// the strings; this dialog does not talk to the controller.
StickyDialog {
    id: dialog

    property string setupCommand: ""
    property string endpoint: ""
    property bool agentWrite: false

    title: qsTr("Connect Claude Code")
    maxWidth: 720
    acceptText: ""
    rejectText: qsTr("Close")

    contentItem: ColumnLayout {
        spacing: 8

        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: qsTr("Run this once in a terminal to register the board's MCP server with Claude Code. The server runs while this window is open.")
        }
        TextArea {
            id: setupCommandArea
            Layout.fillWidth: true
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            font.family: "monospace"
            text: dialog.setupCommand
        }
        RowLayout {
            Button {
                text: qsTr("Copy command")
                onClicked: {
                    setupCommandArea.selectAll()
                    setupCommandArea.copy()
                    setupCommandArea.deselect()
                    copiedLabel.visible = true
                }
            }
            Label { id: copiedLabel; visible: false; text: qsTr("Copied"); color: Theme.agentReadWrite }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Theme.subtleText
            text: qsTr("REST API: %1/api/v1 (same bearer token)\nAgent write access is currently %2. Toggle it from the Agent menu.")
                  .arg(dialog.endpoint)
                  .arg(dialog.agentWrite ? qsTr("enabled") : qsTr("disabled"))
        }
    }
    onOpened: copiedLabel.visible = false
}
