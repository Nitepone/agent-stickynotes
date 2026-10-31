import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Reusable confirmation / message dialog driven by `ask()` and `inform()`.
StickyDialog {
    id: dialog

    property string message: ""
    property string confirmText: qsTr("OK")
    property bool destructive: false
    property bool informational: false
    property var confirmCallback: null

    function ask(title, message, confirmText, destructive, callback) {
        dialog.title = title
        dialog.message = message
        dialog.confirmText = confirmText
        dialog.destructive = destructive
        dialog.informational = false
        dialog.confirmCallback = callback
        open()
    }

    function inform(title, message) {
        dialog.title = title
        dialog.message = message
        dialog.confirmText = qsTr("OK")
        dialog.destructive = false
        dialog.informational = true
        dialog.confirmCallback = null
        open()
    }

    maxWidth: 460
    acceptText: confirmText
    acceptDanger: destructive
    acceptCloses: true
    rejectText: informational ? "" : qsTr("Cancel")

    contentItem: Label {
        text: dialog.message
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }

    onAccepted: {
        const callback = confirmCallback
        confirmCallback = null
        if (callback)
            callback()
    }
}
