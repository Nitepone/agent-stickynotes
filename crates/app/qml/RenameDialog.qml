import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Rename the board; emits `renameRequested` with the new title.
StickyDialog {
    id: dialog

    signal renameRequested(string title)

    function openWith(title) {
        renameField.text = title
        open()
        renameField.selectAll()
        renameField.forceActiveFocus()
    }

    title: qsTr("Rename board")
    maxWidth: 400
    acceptHighlighted: false
    acceptCloses: true

    contentItem: TextField {
        id: renameField
        onAccepted: dialog.accept()
    }

    onAccepted: renameRequested(renameField.text)
}
