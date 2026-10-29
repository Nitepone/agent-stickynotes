import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StickyNotes

// Project-level instructions that agents read (via the project_get tool and
// the exported skill). Only the user can edit these.
Dialog {
    id: dialog

    property string errorText: ""

    signal saveRequested(string documentPrompt, string codeGuidance)

    function openProject(projectJson) {
        const project = JSON.parse(projectJson)
        documentField.text = project.documentPrompt
        codeField.text = project.codeGuidance
        errorText = ""
        open()
        documentField.forceActiveFocus()
    }

    title: qsTr("Project settings")
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(680, (parent ? parent.width : 680) - 40)
    height: Math.min(640, (parent ? parent.height : 640) - 40)
    padding: 16

    contentItem: ScrollView {
        id: scroll
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 6

            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: 12
                text: qsTr("Agents read these through the project_get tool before they work, and they are included when you export the Claude Code skill. Agents cannot change them.")
            }

            SectionLabel { text: qsTr("Document generation") }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: 12
                text: qsTr("How agents should write documents: specs, reports, release notes, tone, structure.")
            }
            FormTextArea {
                id: documentField
                objectName: "documentField"
                Layout.fillWidth: true
                Layout.minimumHeight: 150
                placeholderText: qsTr("e.g. Write in plain English. Start every spec with a one-paragraph summary.")
            }

            SectionLabel { text: qsTr("Code guidance") }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: 12
                text: qsTr("How code for this project should be written: languages, style, structure, testing.")
            }
            FormTextArea {
                id: codeField
                objectName: "codeField"
                Layout.fillWidth: true
                Layout.minimumHeight: 150
                placeholderText: qsTr("e.g. Rust 2024. Keep functions small. Every change needs a test.")
            }

            Label {
                Layout.fillWidth: true
                visible: dialog.errorText !== ""
                text: dialog.errorText
                color: Theme.danger
                wrapMode: Text.Wrap
            }
        }
    }

    footer: DialogButtonBox {
        Button {
            text: qsTr("Cancel")
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            objectName: "saveProject"
            text: qsTr("Save")
            highlighted: true
            DialogButtonBox.buttonRole: DialogButtonBox.ApplyRole
            onClicked: dialog.saveRequested(documentField.text, codeField.text)
        }
    }
}
