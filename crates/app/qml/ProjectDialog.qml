import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StickyNotes

// Project-level instructions that agents read (via the project_get tool and
// the exported skill). Only the user can edit these.
Dialog {
    id: dialog

    property string errorText: ""
    // Every file in the project's artifacts folder: [{ name, kind, size, tasks: [numbers] }].
    property var artifacts: []

    signal saveRequested(string documentPrompt, string codeGuidance)
    signal artifactClicked(string name)

    function openProject(projectJson) {
        const project = JSON.parse(projectJson)
        documentField.text = project.documentPrompt
        codeField.text = project.codeGuidance
        artifacts = project.artifacts || []
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

            SectionLabel { text: qsTr("Artifacts") }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: 12
                text: dialog.artifacts.length === 0
                    ? qsTr("No files in this project's artifacts folder yet.")
                    : qsTr("Every file in this project's artifacts folder. Detached files stay here until you delete them from the folder.")
            }
            Repeater {
                model: dialog.artifacts
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6

                    Button {
                        objectName: "artifactLink"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        flat: true
                        text: modelData.name
                        contentItem: Label {
                            text: parent.text
                            elide: Text.ElideRight
                            color: Theme.link
                            font.underline: parent.hovered
                        }
                        onClicked: dialog.artifactClicked(modelData.name)
                    }
                    Label {
                        objectName: "artifactTasks"
                        text: modelData.tasks.length > 0
                            ? modelData.tasks.map(n => "#" + n).join(", ")
                            : qsTr("not attached")
                        color: Theme.subtleText
                        font.pixelSize: 12
                    }
                }
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
