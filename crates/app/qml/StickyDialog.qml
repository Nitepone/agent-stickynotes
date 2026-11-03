import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Base for every dialog: modal, centred over the window, padded, clamped to
// the window width, with a Cancel / accept footer.
//
// The accept button emits `acceptClicked()`. By default it does not close the
// dialog (the owner closes it once a save succeeded); set `acceptCloses` to
// get the standard Accept role, which closes and emits `accepted()`. Extra
// footer buttons go in `footerButtons: [ Button { ... } ]` and may carry their own button role.
// Dialogs that show an error put an `ErrorLabel { text: dialog.errorText }`
// in their content.
Dialog {
    id: dialog

    // Widest the dialog gets; 0 keeps the content's natural width.
    property real maxWidth: 0
    property string errorText: ""

    property string acceptText: qsTr("Save")       // empty hides the accept button
    property string rejectText: qsTr("Cancel")     // empty hides the reject button
    property bool acceptEnabled: true
    property bool acceptHighlighted: true
    property bool acceptDanger: false
    property bool acceptCloses: false
    property string acceptObjectName: ""

    signal acceptClicked()

    property alias footerButtons: buttonBox.contentData

    modal: true
    anchors.centerIn: Overlay.overlay
    padding: Theme.px(16)

    Binding on width {
        when: dialog.maxWidth > 0
        value: Math.min(dialog.maxWidth, (dialog.parent ? dialog.parent.width : dialog.maxWidth) - Theme.px(40))
    }

    // A hidden button would still take up a slot in the button box, so a
    // button the dialog does not want is taken out of the box instead.
    function syncButton(button, wanted) {
        let at = -1
        for (let i = 0; i < buttonBox.count; ++i)
            if (buttonBox.itemAt(i) === button)
                at = i
        if (wanted && at < 0)
            buttonBox.addItem(button)
        else if (!wanted && at >= 0)
            buttonBox.takeItem(at)
        button.visible = wanted
    }
    onRejectTextChanged: syncButton(rejectButton, rejectText !== "")
    onAcceptTextChanged: syncButton(acceptButton, acceptText !== "")
    Component.onCompleted: {
        syncButton(rejectButton, rejectText !== "")
        syncButton(acceptButton, acceptText !== "")
    }

    footer: DialogButtonBox {
        id: buttonBox

        Button {
            id: rejectButton
            text: dialog.rejectText
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            id: acceptButton
            objectName: dialog.acceptObjectName
            text: dialog.acceptText
            highlighted: dialog.acceptHighlighted && !dialog.acceptDanger
            enabled: dialog.acceptEnabled
            palette.button: dialog.acceptDanger ? Theme.danger : dialog.palette.button
            palette.buttonText: dialog.acceptDanger ? Theme.textOnDanger : dialog.palette.buttonText
            DialogButtonBox.buttonRole: dialog.acceptCloses ? DialogButtonBox.AcceptRole : DialogButtonBox.ApplyRole
            onClicked: dialog.acceptClicked()
        }
    }
}
