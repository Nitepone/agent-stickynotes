import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Choose a project from the projects folder, make a new one, or browse for a
// folder. With `saving` set the board has no project yet, so only creating
// one makes sense.
StickyDialog {
    id: dialog

    property bool saving: false
    property string root: ""
    property var projects: []

    signal openRequested(string dir)
    signal createRequested(string name)
    signal browseRequested()

    function openPicker(projectsJson, forSaving) {
        const data = JSON.parse(projectsJson)
        root = data.root
        projects = data.projects
        saving = forSaving === true
        nameField.text = ""
        open()
        const target = saving || projects.length === 0 ? nameField : list
        target.forceActiveFocus()
    }

    function create() {
        const name = nameField.text.trim()
        if (name !== "")
            createRequested(name)
    }

    title: saving ? qsTr("Save as a new project") : qsTr("Projects")
    maxWidth: 520
    height: Math.min(520, (parent ? parent.height : 520) - 40)
    acceptText: ""
    rejectText: qsTr("Close")

    contentItem: ColumnLayout {
        spacing: 10

        Label {
            Layout.fillWidth: true
            visible: dialog.saving
            wrapMode: Text.Wrap
            color: Theme.subtleText
            text: qsTr("This board is not in a project yet. Name a project to save it in.")
        }

        ListView {
            id: list
            objectName: "projectList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !dialog.saving
            clip: true
            model: dialog.projects
            keyNavigationEnabled: true
            currentIndex: -1

            delegate: ItemDelegate {
                required property var modelData
                width: ListView.view.width
                highlighted: modelData.current
                objectName: "project-" + modelData.title
                onClicked: dialog.openRequested(modelData.dir)
                contentItem: ColumnLayout {
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: modelData.title + (modelData.current ? qsTr("  (open)") : "")
                        font.bold: true
                        elide: Text.ElideRight
                        color: modelData.current ? Theme.textOnPrimary : Theme.text
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.dir
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                        color: modelData.current ? Theme.textOnPrimary : Theme.subtleText
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                width: parent.width - 32
                visible: dialog.projects.length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.subtleText
                text: qsTr("No projects yet in %1.\nCreate one below.").arg(dialog.root)
            }
        }

        SectionLabel { text: qsTr("New project") }
        RowLayout {
            Layout.fillWidth: true
            TextField {
                id: nameField
                objectName: "nameField"
                Layout.fillWidth: true
                placeholderText: qsTr("Project name")
                onAccepted: dialog.create()
            }
            Button {
                objectName: "createButton"
                text: qsTr("Create")
                highlighted: true
                enabled: nameField.text.trim() !== ""
                onClicked: dialog.create()
            }
        }

        Label {
            Layout.fillWidth: true
            visible: !dialog.saving
            wrapMode: Text.WrapAnywhere
            color: Theme.subtleText
            font.pixelSize: 11
            text: qsTr("Projects are kept in %1").arg(dialog.root)
        }
    }

    footerButtons: [
        Button {
            objectName: "browseButton"
            visible: !dialog.saving
            text: qsTr("Browse…")
            onClicked: dialog.browseRequested()
        }
    ]
}
