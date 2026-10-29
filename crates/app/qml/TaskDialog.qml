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
    // Every task on the board as { id, columnTitle, text, label }, supplied by
    // the owner so the dialog can offer link targets.
    property var linkCandidates: []
    // [{ value, label }] of the relations a link can have.
    property var relationOptions: []
    property string loadedForm: ""

    // Link targets: all tasks except this one.
    readonly property var linkTargets: linkCandidates.filter(c => c.id !== taskId)

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
    signal openTaskRequested(string taskId)

    // True if the form differs from what was loaded.
    function isEdited() {
        return formJson() !== loadedForm
    }

    function openNew(column) {
        clearForm()
        columnId = column.id
        columnTitle = column.title
        loadedForm = formJson()
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
        referencesModel.clear()
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
        referencesModel.clear()
        for (const r of task.references)
            referencesModel.append({
                tid: r.taskId, relation: r.relation, relationLabel: r.relationLabel,
                description: r.description, columnTitle: r.columnTitle })
        targetBox.currentIndex = -1
        loadedForm = formJson()
    }

    // Add a link (or change the relation of an existing link to that task).
    function addReference(targetId, relation) {
        const target = linkTargets.find(c => c.id === targetId)
        const option = relationOptions.find(o => o.value === relation)
        if (!target || !option)
            return
        for (let i = referencesModel.count - 1; i >= 0; i--)
            if (referencesModel.get(i).tid === targetId)
                referencesModel.remove(i)
        referencesModel.append({
            tid: targetId, relation: relation, relationLabel: option.label,
            description: target.text, columnTitle: target.columnTitle })
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
        const form = {
            description: descriptionField.text,
            extendedDescription: extendedField.text,
            requirements: requirements,
            criteria: criteria,
        }
        // A new task has no id yet, so it cannot be linked until it is saved.
        if (!creating) {
            form.references = []
            for (let i = 0; i < referencesModel.count; i++) {
                const r = referencesModel.get(i)
                form.references.push({ task: r.tid, relation: r.relation })
            }
        }
        return JSON.stringify(form)
    }

    title: creating ? qsTr("New task in %1").arg(columnTitle) : qsTr("Task in %1").arg(columnTitle)
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(640, (parent ? parent.width : 640) - 40)
    height: Math.min(760, (parent ? parent.height : 760) - 40)
    padding: 16

    ListModel { id: requirementsModel }
    ListModel { id: criteriaModel }
    ListModel { id: referencesModel }

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
                    spacing: 6
                    Label {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 8
                        text: "•"
                        color: Theme.subtleText
                    }
                    WrappingField {
                        objectName: "requirementField"
                        Layout.fillWidth: true
                        text: parent.text
                        placeholderText: qsTr("Requirement")
                        onTextChanged: requirementsModel.setProperty(parent.index, "text", text)
                    }
                    ToolButton {
                        Layout.alignment: Qt.AlignTop
                        objectName: "removeRequirement"
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
                    spacing: 6
                    CheckBox {
                        Layout.alignment: Qt.AlignTop
                        objectName: "criterionCheck"
                        checked: parent.done
                        onToggled: criteriaModel.setProperty(parent.index, "done", checked)
                    }
                    WrappingField {
                        objectName: "criterionField"
                        Layout.fillWidth: true
                        text: parent.text
                        placeholderText: qsTr("Acceptance criterion")
                        onTextChanged: criteriaModel.setProperty(parent.index, "text", text)
                    }
                    ToolButton {
                        Layout.alignment: Qt.AlignTop
                        objectName: "removeCriterion"
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

            SectionLabel { text: qsTr("References") }
            Label {
                Layout.fillWidth: true
                visible: dialog.creating
                text: qsTr("Save the task first, then reopen it to link it to other tasks.")
                color: Theme.subtleText
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            Repeater {
                model: referencesModel
                delegate: RowLayout {
                    required property int index
                    required property string tid
                    required property string relationLabel
                    required property string description
                    required property string columnTitle
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        objectName: "referenceRelation"
                        text: parent.relationLabel
                        color: Theme.subtleText
                        Layout.minimumWidth: 100
                    }
                    Button {
                        objectName: "referenceLink"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        flat: true
                        text: parent.description
                        contentItem: Label {
                            text: parent.text
                            elide: Text.ElideRight
                            color: Theme.dropIndicator
                            font.underline: parent.hovered
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Open this task")
                        onClicked: dialog.openTaskRequested(parent.tid)
                    }
                    Label {
                        text: parent.columnTitle
                        color: Theme.subtleText
                        font.pixelSize: 12
                    }
                    ToolButton {
                        objectName: "removeReference"
                        text: "\u2715"
                        onClicked: referencesModel.remove(parent.index)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: !dialog.creating
                spacing: 6

                ComboBox {
                    id: relationBox
                    objectName: "relationBox"
                    Layout.preferredWidth: 140
                    model: dialog.relationOptions
                    textRole: "label"
                    valueRole: "value"
                }
                ComboBox {
                    id: targetBox
                    objectName: "targetBox"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    model: dialog.linkTargets
                    textRole: "label"
                    valueRole: "id"
                    displayText: currentIndex < 0 ? qsTr("Choose a task\u2026") : currentText
                    currentIndex: -1
                    // ComboBox selects the first entry whenever its model
                    // changes; we want an explicit choice.
                    onCountChanged: currentIndex = -1
                }
                Button {
                    objectName: "addReference"
                    text: qsTr("Add")
                    enabled: targetBox.currentIndex >= 0 && relationBox.currentIndex >= 0
                    onClicked: {
                        dialog.addReference(targetBox.currentValue, relationBox.currentValue)
                        targetBox.currentIndex = -1
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
