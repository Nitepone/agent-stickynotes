import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Pick a backup of the board and replace the open board with it. Emits
// `restoreRequested(name)` only after a second, confirming click.
StickyDialog {
    id: dialog

    property var backups: []
    property string selected: ""
    property bool confirming: false

    signal restoreRequested(string name)

    function openWith(json) {
        backups = JSON.parse(json)
        selected = ""
        confirming = false
        open()
    }

    function rowLabel(b) {
        const kind = b.isBak ? qsTr("before last save") : qsTr("snapshot")
        return b.readable
            ? qsTr("%1  %2  (%n task(s))", "", b.tasks).arg(b.time).arg(kind)
            : qsTr("%1  %2  (unreadable)").arg(b.time).arg(kind)
    }

    title: qsTr("Restore from backup")
    maxWidth: 520
    acceptText: confirming ? qsTr("Replace board") : qsTr("Restore…")
    acceptEnabled: selected !== ""
    acceptDanger: confirming
    acceptObjectName: "restoreButton"
    onSelectedChanged: confirming = false

    onAcceptClicked: {
        if (!confirming) {
            confirming = true
            return
        }
        const name = selected
        close()
        restoreRequested(name)
    }

    contentItem: ColumnLayout {
        spacing: 10

        Label {
            Layout.fillWidth: true
            visible: dialog.backups.length === 0
            objectName: "noBackups"
            text: qsTr("There are no backups yet. They are made when the board is saved.")
            wrapMode: Text.Wrap
        }

        ListView {
            id: list
            objectName: "backupList"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 260)
            visible: dialog.backups.length > 0
            clip: true
            model: dialog.backups
            delegate: ItemDelegate {
                required property var modelData
                objectName: "backupRow"
                width: ListView.view.width
                text: dialog.rowLabel(modelData)
                enabled: modelData.readable
                highlighted: modelData.name === dialog.selected
                onClicked: dialog.selected = modelData.name
            }
        }

        Label {
            Layout.fillWidth: true
            visible: dialog.confirming
            objectName: "confirmText"
            text: qsTr("This replaces the open board with the chosen backup. The current file is snapshotted first, and the restored board stays unsaved until you save it. Undo history is cleared.")
            wrapMode: Text.Wrap
            color: Theme.warning
        }
    }
}
