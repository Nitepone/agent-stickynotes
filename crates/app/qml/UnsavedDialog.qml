import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// "Save first?" prompt shown before an action that would drop unsaved changes.
// `pending` is the action to continue with; it is handed back with the signal.
StickyDialog {
    id: dialog

    property var pending: null

    signal saveRequested(var next)
    signal discardRequested(var next)

    title: qsTr("Unsaved changes")
    acceptText: qsTr("Save")
    acceptHighlighted: false
    acceptCloses: true

    Label { text: qsTr("The board has unsaved changes. Save them first?") }

    footerButtons: [
        Button {
            text: qsTr("Discard")
            DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
            onClicked: {
                const next = dialog.pending
                dialog.pending = null
                dialog.close()
                dialog.discardRequested(next)
            }
        }
    ]

    onAccepted: {
        const next = pending
        pending = null
        saveRequested(next)
    }
    onRejected: pending = null
}
