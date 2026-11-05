import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// The project's name (the board title) and the instructions agents read (via
// the project_get tool and the exported skill). Only the user can edit these.
StickyDialog {
    id: dialog

    // Every file in the project's artifacts folder: [{ name, kind, size, tasks: [numbers] }].
    property var artifacts: []

    signal saveRequested(string title, string documentPrompt, string codeGuidance)
    signal artifactClicked(string name)

    // With `focusName` the name is selected, ready to type over (clicking the
    // board title); otherwise the cursor starts in the document prompt.
    function openProject(projectJson, focusName) {
        const project = JSON.parse(projectJson)
        nameField.text = project.title || ""
        nameField.invalid = false
        documentField.text = project.documentPrompt
        codeField.text = project.codeGuidance
        artifacts = project.artifacts || []
        errorText = ""
        open()
        if (focusName === true) {
            nameField.selectAll()
            nameField.forceActiveFocus()
        } else {
            documentField.forceActiveFocus()
        }
    }

    function save() {
        if (nameField.text.trim().length === 0) {
            nameField.invalid = true
            errorText = qsTr("The project needs a name.")
            nameField.forceActiveFocus()
            return
        }
        saveRequested(nameField.text, documentField.text, codeField.text)
    }

    title: qsTr("Project settings")
    maxWidth: Theme.px(680)
    height: Math.min(Theme.px(700), (parent ? parent.height : Theme.px(700)) - Theme.px(40))
    acceptObjectName: "saveProject"
    onAcceptClicked: save()

    contentItem: ScrollView {
        id: scroll
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: scroll.availableWidth
            spacing: Theme.px(6)

            SectionLabel { text: qsTr("Name *"); Layout.topMargin: 0 }
            FormTextField {
                id: nameField
                objectName: "nameField"
                Layout.fillWidth: true
                Accessible.name: qsTr("Project name")
                placeholderText: qsTr("Shown as the board title and in the project list")
                onAccepted: dialog.save()
                onTextEdited: if (dialog.errorText !== "") dialog.errorText = ""
            }

            SectionLabel { text: qsTr("Agent instructions") }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: Theme.fs(12)
                text: qsTr("Agents read these through the project_get tool before they work, and they are included when you export the Claude Code skill. Agents cannot change them.")
            }

            SectionLabel { text: qsTr("Document generation") }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: Theme.fs(12)
                text: qsTr("How agents should write documents: specs, reports, release notes, tone, structure.")
            }
            FormTextArea {
                id: documentField
                objectName: "documentField"
                Layout.fillWidth: true
                Layout.minimumHeight: Theme.px(150)
                placeholderText: qsTr("e.g. Write in plain English. Start every spec with a one-paragraph summary.")
            }

            SectionLabel { text: qsTr("Code guidance") }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: Theme.fs(12)
                text: qsTr("How code for this project should be written: languages, style, structure, testing.")
            }
            FormTextArea {
                id: codeField
                objectName: "codeField"
                Layout.fillWidth: true
                Layout.minimumHeight: Theme.px(150)
                placeholderText: qsTr("e.g. Rust 2024. Keep functions small. Every change needs a test.")
            }

            SectionLabel { text: qsTr("Artifacts") }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: Theme.fs(12)
                text: dialog.artifacts.length === 0
                    ? qsTr("No files in this project's artifacts folder yet.")
                    : qsTr("Every file in this project's artifacts folder. Detached files stay here until you delete them from the folder.")
            }
            Repeater {
                model: dialog.artifacts
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.px(6)

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
                        font.pixelSize: Theme.fs(12)
                    }
                }
            }

            ErrorLabel { text: dialog.errorText }
        }
    }
}
