import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StickyNotes

// Create or edit a task. Emits `saveRequested` with a JSON form; the caller
// applies it and closes the dialog on success.
Dialog {
    id: dialog

    property string taskId: ""          // empty when creating
    property string columnId: ""
    property string columnTitle: ""
    property string loadedUpdatedAt: ""
    property bool changedExternally: false
    property bool deletedExternally: false
    property string errorText: ""

    readonly property bool creating: taskId === ""
    readonly property int criteriaDone: {
        let n = 0
        for (let i = 0; i < criteriaModel.count; i++)
            if (criteriaModel.get(i).done) n++
        return n
    }

    signal saveRequested(string taskId, string columnId, string formJson)
    signal deleteRequested(string taskId)
    signal reloadRequested(string taskId)

    function openNew(column) {
        clearForm()
        columnId = column.id
        columnTitle = column.title
        open()
        descriptionField.forceActiveFocus()
    }

    function openTask(taskJson, title) {
        clearForm()
        load(JSON.parse(taskJson))
        columnTitle = title
        open()
    }

    // Called by the owner whenever the board changes while we are open.
    function boardChanged(taskJson) {
        if (!visible || creating)
            return
        if (taskJson === "") {
            deletedExternally = true
            return
        }
        changedExternally = JSON.parse(taskJson).updatedAt !== loadedUpdatedAt
    }

    function clearForm() {
        taskId = ""
        columnId = ""
        loadedUpdatedAt = ""
        changedExternally = false
        deletedExternally = false
        errorText = ""
        descriptionField.text = ""
        extendedField.text = ""
        requirementsModel.clear()
        criteriaModel.clear()
    }

    function load(task) {
        taskId = task.id
        columnId = task.columnId
        loadedUpdatedAt = task.updatedAt
        changedExternally = false
        descriptionField.text = task.description
        extendedField.text = task.extendedDescription
        requirementsModel.clear()
        for (const r of task.requirements)
            requirementsModel.append({ text: r })
        criteriaModel.clear()
        for (const c of task.criteria)
            criteriaModel.append({ cid: c.id, text: c.text, done: c.done })
    }

    function formJson() {
        const requirements = []
        for (let i = 0; i < requirementsModel.count; i++)
            requirements.push(requirementsModel.get(i).text)
        const criteria = []
        for (let i = 0; i < criteriaModel.count; i++) {
            const c = criteriaModel.get(i)
            criteria.push({ id: c.cid, text: c.text, done: c.done })
        }
        return JSON.stringify({
            description: descriptionField.text,
            extendedDescription: extendedField.text,
            requirements: requirements,
            criteria: criteria,
        })
    }

    title: creating ? qsTr("New task in %1").arg(columnTitle) : qsTr("Task in %1").arg(columnTitle)
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(640, (parent ? parent.width : 640) - 40)
    height: Math.min(760, (parent ? parent.height : 760) - 40)
    padding: 16

    ListModel { id: requirementsModel }
    ListModel { id: criteriaModel }

    contentItem: ScrollView {
        id: scroll
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                visible: dialog.changedExternally || dialog.deletedExternally
                implicitHeight: bannerRow.implicitHeight + 16
                radius: 6
                color: "#fef3c7"
                border.color: Theme.warning

                RowLayout {
                    id: bannerRow
                    anchors.fill: parent
                    anchors.margins: 8
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: dialog.deletedExternally
                              ? qsTr("This task was deleted while you were editing it.")
                              : qsTr("This task was changed (possibly by an agent) while you were editing it.")
                    }
                    Button {
                        visible: !dialog.deletedExternally
                        text: qsTr("Reload")
                        onClicked: dialog.reloadRequested(dialog.taskId)
                    }
                }
            }

            SectionLabel { text: qsTr("Description *") }
            FormTextArea {
                id: descriptionField
                Layout.fillWidth: true
                Layout.minimumHeight: 70
                placeholderText: qsTr("Short, sticky-note sized summary")
            }
            Label {
                Layout.alignment: Qt.AlignRight
                readonly property int length: descriptionField.text.trim().length
                text: qsTr("%1 / %2 suggested").arg(length).arg(Theme.suggestedDescriptionChars)
                color: length > Theme.suggestedDescriptionChars ? Theme.warning : Theme.subtleText
                font.pixelSize: 12
            }

            SectionLabel { text: qsTr("Extended description") }
            FormTextArea {
                id: extendedField
                Layout.fillWidth: true
                Layout.minimumHeight: 110
                placeholderText: qsTr("Optional details, context, links…")
            }

            SectionLabel { text: qsTr("Requirements") }
            Repeater {
                model: requirementsModel
                delegate: RowLayout {
                    required property int index
                    required property string text
                    Layout.fillWidth: true
                    Label { text: "•"; color: Theme.subtleText }
                    TextField {
                        Layout.fillWidth: true
                        text: parent.text
                        placeholderText: qsTr("Requirement")
                        onTextEdited: requirementsModel.setProperty(parent.index, "text", text)
                    }
                    ToolButton {
                        text: "✕"
                        onClicked: requirementsModel.remove(parent.index)
                    }
                }
            }
            Button {
                text: qsTr("+ Add requirement")
                flat: true
                onClicked: requirementsModel.append({ text: "" })
            }

            SectionLabel {
                text: criteriaModel.count > 0
                      ? qsTr("Acceptance criteria (%1/%2)").arg(dialog.criteriaDone).arg(criteriaModel.count)
                      : qsTr("Acceptance criteria")
            }
            Repeater {
                model: criteriaModel
                delegate: RowLayout {
                    required property int index
                    required property string text
                    required property bool done
                    Layout.fillWidth: true
                    CheckBox {
                        checked: parent.done
                        onToggled: criteriaModel.setProperty(parent.index, "done", checked)
                    }
                    TextField {
                        Layout.fillWidth: true
                        text: parent.text
                        placeholderText: qsTr("Acceptance criterion")
                        onTextEdited: criteriaModel.setProperty(parent.index, "text", text)
                    }
                    ToolButton {
                        text: "✕"
                        onClicked: criteriaModel.remove(parent.index)
                    }
                }
            }
            Button {
                text: qsTr("+ Add criterion")
                flat: true
                onClicked: criteriaModel.append({ cid: "", text: "", done: false })
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
            text: qsTr("Delete")
            visible: !dialog.creating
            DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
            onClicked: dialog.deleteRequested(dialog.taskId)
        }
        Button {
            text: qsTr("Cancel")
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            text: qsTr("Save")
            highlighted: true
            enabled: descriptionField.text.trim().length > 0 && !dialog.deletedExternally
            DialogButtonBox.buttonRole: DialogButtonBox.ApplyRole
            onClicked: dialog.saveRequested(dialog.taskId, dialog.columnId, dialog.formJson())
        }
    }
}
