import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StickyNotes

// Reusable confirmation / message dialog driven by `ask()` and `inform()`.
Dialog {
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

    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(460, (parent ? parent.width : 460) - 40)
    padding: 16

    contentItem: Label {
        text: dialog.message
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }

    footer: DialogButtonBox {
        Button {
            text: qsTr("Cancel")
            visible: !dialog.informational
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            text: dialog.confirmText
            visible: !dialog.destructive
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
        Button {
            text: dialog.confirmText
            visible: dialog.destructive
            palette.button: Theme.danger
            palette.buttonText: "white"
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }

    onAccepted: {
        const callback = confirmCallback
        confirmCallback = null
        if (callback)
            callback()
    }
}
