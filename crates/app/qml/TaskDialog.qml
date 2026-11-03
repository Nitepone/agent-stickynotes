import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import QtQuick.Dialogs
import StickyNotes

// Create or edit a task. Emits `saveRequested` with a JSON form; the caller
// applies it and closes the dialog on success.
StickyDialog {
    id: dialog

    property string taskId: ""          // empty when creating
    property int taskNumber: 0          // read-only; assigned when the task is created
    property string columnId: ""
    property string columnTitle: ""
    property string loadedUpdatedAt: ""
    property bool changedExternally: false
    property bool deletedExternally: false
    // Every task on the board as { id, columnTitle, text, label }, supplied by
    // the owner so the dialog can offer link targets.
    property var linkCandidates: []
    // Categories already used on the board, for the drop-down.
    property var categories: []
    // What is in the category box right now (typed or chosen), as typed.
    property string categoryText: ""
    // [{ value, label }] of the relations a link can have.
    property var relationOptions: []
    property string loadedForm: ""
    // Finds misspelled words for the text fields (see SpellUnderline); null for none.
    property var spellRanges: null
    // Why the last attach failed; shown in the Artifacts section.
    property string attachError: ""
    // A file is being dragged over the dialog (it will be attached on drop).
    property bool dragOver: false
    // True while a text field has the keyboard, so Ctrl+V pastes text there.
    readonly property var focusedItem:
        contentItem && contentItem.Window.window ? contentItem.Window.window.activeFocusItem : null
    readonly property bool textFocused: focusedItem !== null && focusedItem.cursorPosition !== undefined
    // What opens the file chooser (anything with open()); tests replace it.
    property var chooser: fileDialog

    // Drafting requirements and criteria with an LLM. The owner runs it and
    // reports back through applyDraft() / showGenerationError().
    property bool generating: false
    property string generatorName: ""
    property string generationNote: ""
    property bool generationNoteIsError: false
    property int generationSeconds: 0
    // Shown under the category box when a draft did not give a usable category.
    property string categoryNote: ""
    // What the lists and category were just before the last draft was applied,
    // as { requirements, criteria, category }; null when there is nothing to undo.
    property var draftSnapshot: null
    readonly property bool hasDraftSnapshot: draftSnapshot !== null

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
    signal artifactClicked(string name)
    // The user chose a file to attach to this (existing) task; the owner
    // copies it into the project and calls artifactsAttached() or sets attachError.
    signal attachRequested(string taskId, url fileUrl)
    // Ctrl+V with no text field focused: the owner attaches the clipboard's
    // image or files, then calls artifactsAttached() or attachFailed().
    signal pasteRequested(string taskId)
    signal generateRequested(string formJson)
    signal cancelGenerationRequested()
    // Asks the owner to confirm; the owner then calls undoDraft().
    signal undoDraftRequested()

    onGeneratingChanged: if (generating) generationSeconds = 0
    // Closing the dialog abandons any draft in progress.
    onClosed: {
        if (generating) cancelGenerationRequested()
        draftSnapshot = null
    }

    function plural(n, one, many) {
        return n === 1 ? one : many
    }

    function takeSnapshot() {
        const requirements = []
        for (let i = 0; i < requirementsModel.count; i++)
            requirements.push(requirementsModel.get(i).text)
        const criteria = []
        for (let i = 0; i < criteriaModel.count; i++) {
            const c = criteriaModel.get(i)
            criteria.push({ cid: c.cid, text: c.text, done: c.done })
        }
        return { requirements: requirements, criteria: criteria, category: categoryText }
    }

    // Add drafted items, and fill the category when the draft chose one and the
    // box is empty (a category the user already set is never replaced). Existing
    // items are kept; nothing is saved here. `category` and `categoryInvalid`
    // are optional. Remembers the state before, for undoDraft().
    function applyDraft(requirements, criteria, category, categoryInvalid) {
        const before = takeSnapshot()
        const fillCategory = !!category && categoryText.trim() === ""
        for (const r of requirements)
            requirementsModel.append({ text: r })
        for (const c of criteria)
            criteriaModel.append({ cid: "", text: c, done: false })
        if (fillCategory) {
            showCategory(category)
            settleCategory()
        }
        if (requirements.length + criteria.length > 0 || fillCategory)
            draftSnapshot = before
        categoryNote = (categoryInvalid && categoryText.trim() === "")
            ? qsTr("The draft did not choose one of the existing categories, so none was set. Pick one yourself if you want one.")
            : ""
        generationNoteIsError = false
        const categoryPart = fillCategory ? qsTr(" Category set to \u201c%1\u201d.").arg(categoryText) : ""
        if (requirements.length + criteria.length === 0) {
            generationNote = qsTr("Nothing new to add: the task already covers what was found.") + categoryPart
            return
        }
        generationNote = qsTr("Added %1 and %2 below. Review and edit them, then Save.")
            .arg(requirements.length + " " + plural(requirements.length, qsTr("requirement"), qsTr("requirements")))
            .arg(criteria.length + " " + plural(criteria.length, qsTr("acceptance criterion"), qsTr("acceptance criteria")))
            + categoryPart
    }

    // Put the requirements, criteria and category back as they were before the
    // last draft, discarding anything changed since. Called once the user has
    // confirmed.
    function undoDraft() {
        const snap = draftSnapshot
        if (snap === null)
            return
        requirementsModel.clear()
        for (const r of snap.requirements)
            requirementsModel.append({ text: r })
        criteriaModel.clear()
        for (const c of snap.criteria)
            criteriaModel.append({ cid: c.cid, text: c.text, done: c.done })
        showCategory(snap.category)
        settleCategory()
        draftSnapshot = null
        categoryNote = ""
        generationNoteIsError = false
        generationNote = qsTr("Draft undone.")
    }

    function showGenerationError(message) {
        generationNoteIsError = true
        generationNote = message
    }

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

    // The text that will be saved as the category: trimmed, in the spelling of
    // an existing category that matches it ignoring case.
    function resolvedCategory() {
        const typed = categoryText.trim()
        const at = categoryIndex(typed)
        return at >= 0 ? categories[at] : typed
    }

    function categoryIndex(text) {
        const wanted = text.trim().toLowerCase()
        if (wanted === "")
            return -1
        return categories.findIndex(c => c.toLowerCase() === wanted)
    }

    // Put `text` in the category box without treating it as typing.
    function showCategory(text) {
        categoryBox.currentIndex = -1
        categoryBox.editText = text
        categoryText = text
    }

    // Typing "ui" when "UI" exists selects "UI" rather than making a near-duplicate.
    function settleCategory() {
        const at = categoryIndex(categoryText)
        if (at >= 0) {
            showCategory(categories[at])
            categoryBox.currentIndex = at
        } else {
            showCategory(categoryText.trim())
        }
    }

    function clearForm() {
        taskId = ""
        taskNumber = 0
        columnId = ""
        loadedUpdatedAt = ""
        changedExternally = false
        deletedExternally = false
        errorText = ""
        attachError = ""
        generationNote = ""
        categoryNote = ""
        draftSnapshot = null
        descriptionField.text = ""
        extendedField.text = ""
        showCategory("")
        requirementsModel.clear()
        criteriaModel.clear()
        referencesModel.clear()
        artifactsModel.clear()
    }

    function load(task) {
        taskId = task.id
        taskNumber = task.number
        columnId = task.columnId
        loadedUpdatedAt = task.updatedAt
        changedExternally = false
        draftSnapshot = null
        categoryNote = ""
        descriptionField.text = task.description
        extendedField.text = task.extendedDescription
        showCategory(task.category || "")
        settleCategory()
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
        attachError = ""
        setArtifacts(task.artifacts)
        targetBox.currentIndex = -1
        loadedForm = formJson()
    }

    function setArtifacts(list) {
        artifactsModel.clear()
        for (const a of list || [])
            artifactsModel.append({
                aname: a.name, akind: a.kind, byAgent: a.byAgent === true,
                addedBy: a.addedBy || "", stage: a.stage || "", addedAt: a.addedAt || "" })
    }

    // The owner attached a file: show the task's artifacts again. Attaching
    // touches the task, so this is not an outside change.
    function artifactsAttached(taskJson) {
        const task = JSON.parse(taskJson)
        setArtifacts(task.artifacts)
        if (!changedExternally)
            loadedUpdatedAt = task.updatedAt
    }

    // One refused file (or reason); several accumulate, one per line.
    function attachFailed(message) {
        attachError = attachError === "" ? message : attachError + "\n" + message
    }

    function cannotAttachYet() {
        attachError = qsTr("Save the task first, then reopen it to attach files.")
    }

    // Files dropped on the dialog: each is checked on its own by the owner.
    function dropFiles(urls) {
        if (creating) {
            cannotAttachYet()
            return
        }
        attachError = ""
        for (const u of urls || [])
            attachRequested(taskId, u)
    }

    // Ctrl+V (no text field focused).
    function pasteFromClipboard() {
        if (creating) {
            cannotAttachYet()
            return
        }
        attachError = ""
        pasteRequested(taskId)
    }

    function chooseFile() {
        attachError = ""
        chooser.open()
    }

    // "You · 3/5/26, 10:12 · in Backlog"; only what is known is shown.
    function artifactMeta(addedBy, byAgent, addedAt, stage) {
        const parts = []
        if (addedBy === "user")
            parts.push(qsTr("You"))
        else if (addedBy !== "")
            parts.push(addedBy)
        else if (byAgent)
            parts.push(qsTr("added by an agent"))
        if (addedAt !== "") {
            const d = new Date(addedAt)
            if (!isNaN(d.getTime()))
                parts.push(Qt.formatDateTime(d, Locale.ShortFormat))
        }
        if (stage !== "")
            parts.push(qsTr("in %1").arg(stage))
        return parts.join(" \u00b7 ")
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
            category: resolvedCategory(),
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
    maxWidth: Theme.px(640)
    height: Math.min(Theme.px(760), (parent ? parent.height : Theme.px(760)) - Theme.px(40))
    acceptEnabled: descriptionField.text.trim().length > 0 && !deletedExternally
    onAcceptClicked: saveRequested(taskId, columnId, formJson())

    ListModel { id: requirementsModel }
    ListModel { id: criteriaModel }
    ListModel { id: referencesModel }
    ListModel { id: artifactsModel }

    FileDialog {
        id: fileDialog
        title: qsTr("Attach a file")
        fileMode: FileDialog.OpenFile
        nameFilters: [
            qsTr("Markdown and images (*.md *.png *.jpg *.jpeg *.gif *.webp *.svg)"),
            qsTr("Markdown (*.md)"),
            qsTr("Images (*.png *.jpg *.jpeg *.gif *.webp *.svg)")]
        onAccepted: dialog.attachRequested(dialog.taskId, selectedFile)
    }

    contentItem: ScrollView {
        id: scroll
        clip: true
        contentWidth: availableWidth

        // Files dragged from a file manager onto the dialog; above the
        // content, but it only takes part in drags.
        DropArea {
            id: dropArea
            parent: scroll
            anchors.fill: parent
            z: 10
            onEntered: (drag) => {
                drag.accepted = drag.hasUrls
                dialog.dragOver = drag.hasUrls
            }
            onExited: dialog.dragOver = false
            onDropped: (drop) => {
                dialog.dragOver = false
                if (drop.hasUrls) {
                    drop.acceptProposedAction()
                    dialog.dropFiles(drop.urls)
                }
            }

            Rectangle {
                objectName: "dropHighlight"
                anchors.fill: parent
                visible: dialog.dragOver
                color: Theme.primary
                opacity: 0.12
                border.color: Theme.primary
                border.width: Theme.px(2)
            }
            // Not enabled while a text field has focus: Ctrl+V pastes text there.
            Shortcut {
                objectName: "pasteShortcut"
                sequences: [StandardKey.Paste]
                enabled: dialog.visible && !dialog.textFocused
                onActivated: dialog.pasteFromClipboard()
            }
        }

        ColumnLayout {
            width: scroll.availableWidth
            spacing: Theme.px(6)

            Rectangle {
                Layout.fillWidth: true
                visible: dialog.changedExternally || dialog.deletedExternally
                implicitHeight: bannerRow.implicitHeight + Theme.px(16)
                radius: Theme.px(6)
                color: Theme.bannerBackground
                border.color: Theme.warning

                RowLayout {
                    id: bannerRow
                    anchors.fill: parent
                    anchors.margins: Theme.px(8)
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

            // The task's permanent number, for referring to it in conversation.
            Label {
                objectName: "taskNumber"
                visible: !dialog.creating
                text: "#" + dialog.taskNumber
                color: Theme.subtleText
                font.pixelSize: Theme.fs(13)
                font.bold: true
                ToolTip.visible: numberHover.hovered
                ToolTip.text: qsTr("Task number: use it to refer to this task, for example when talking to an agent.")
                HoverHandler { id: numberHover }
            }

            SectionLabel { text: qsTr("Description *") }
            FormTextArea {
                id: descriptionField
                objectName: "descriptionField"
                spellRanges: dialog.spellRanges
                Layout.fillWidth: true
                Layout.minimumHeight: Theme.px(70)
                placeholderText: qsTr("Short, sticky-note sized summary")
            }
            Label {
                Layout.alignment: Qt.AlignRight
                readonly property int length: descriptionField.text.trim().length
                text: qsTr("%1 / %2 suggested").arg(length).arg(Theme.suggestedDescriptionChars)
                color: length > Theme.suggestedDescriptionChars ? Theme.warning : Theme.subtleText
                font.pixelSize: Theme.fs(12)
            }

            SectionLabel { text: qsTr("Extended description") }
            FormTextArea {
                id: extendedField
                spellRanges: dialog.spellRanges
                Layout.fillWidth: true
                Layout.minimumHeight: Theme.px(110)
                placeholderText: qsTr("Optional details, context, links…")
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.px(8)
                spacing: Theme.px(8)

                Button {
                    objectName: "generateButton"
                    visible: !dialog.generating
                    text: qsTr("Draft requirements && criteria")
                    enabled: descriptionField.text.trim().length > 0
                    onClicked: {
                        dialog.generationNote = ""
                        dialog.categoryNote = ""
                        dialog.generateRequested(dialog.formJson())
                    }
                    ToolTip.visible: hovered
                    ToolTip.delay: 600
                    ToolTip.text: qsTr("Ask %1 to propose requirements and acceptance criteria from the descriptions. Nothing is saved until you click Save.")
                                  .arg(dialog.generatorName)
                }
                Button {
                    objectName: "undoDraftButton"
                    visible: dialog.hasDraftSnapshot && !dialog.generating
                    text: qsTr("Undo draft")
                    onClicked: dialog.undoDraftRequested()
                    Accessible.name: qsTr("Undo the drafted requirements and criteria")
                    ToolTip.visible: hovered
                    ToolTip.delay: 600
                    ToolTip.text: qsTr("Remove what the draft added and restore the task as it was before it.")
                }
                BusyIndicator {
                    objectName: "generatingIndicator"
                    visible: dialog.generating
                    running: dialog.generating
                    implicitWidth: Theme.px(28)
                    implicitHeight: Theme.px(28)
                }
                Label {
                    objectName: "generatingLabel"
                    visible: dialog.generating
                    text: qsTr("Asking %1\u2026 %2 s").arg(dialog.generatorName).arg(dialog.generationSeconds)
                    color: Theme.subtleText
                }
                Button {
                    objectName: "cancelGeneration"
                    visible: dialog.generating
                    text: qsTr("Cancel")
                    onClicked: dialog.cancelGenerationRequested()
                }
                Item { Layout.fillWidth: true }

                Timer {
                    interval: 1000
                    repeat: true
                    running: dialog.generating
                    onTriggered: dialog.generationSeconds++
                }
            }
            Label {
                objectName: "generationNote"
                Layout.fillWidth: true
                visible: dialog.generationNote !== ""
                text: dialog.generationNote
                wrapMode: Text.Wrap
                color: dialog.generationNoteIsError ? Theme.danger : Theme.success
            }

            SectionLabel { text: qsTr("Category") }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(6)

                ComboBox {
                    id: categoryBox
                    objectName: "categoryBox"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    editable: true
                    model: dialog.categories
                    currentIndex: -1
                    Accessible.name: qsTr("Category")
                    // ComboBox selects the first entry whenever its model changes;
                    // keep what the user typed or chose instead.
                    onCountChanged: dialog.showCategory(dialog.categoryText)
                    // Only the user's typing counts; the box also rewrites its own
                    // text when the model changes.
                    Connections {
                        target: categoryBox.contentItem
                        function onTextEdited() { dialog.categoryText = categoryBox.contentItem.text }
                    }
                    onAccepted: dialog.settleCategory()
                    onActivated: {
                        dialog.categoryText = currentText
                        dialog.settleCategory()
                    }
                    onActiveFocusChanged: if (!activeFocus) dialog.settleCategory()
                }
                ToolButton {
                    objectName: "clearCategory"
                    text: "\u2715"
                    enabled: dialog.categoryText.trim() !== ""
                    Accessible.name: qsTr("Clear category")
                    onClicked: dialog.showCategory("")
                    ToolTip.visible: hovered
                    ToolTip.delay: 600
                    ToolTip.text: qsTr("Clear the category")
                }
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("Tasks of the same category in a column stack together. Pick one or type a new name.")
                color: Theme.subtleText
                font.pixelSize: Theme.fs(12)
                wrapMode: Text.Wrap
            }
            Label {
                objectName: "categoryNote"
                Layout.fillWidth: true
                visible: dialog.categoryNote !== ""
                text: dialog.categoryNote
                color: Theme.warning
                font.pixelSize: Theme.fs(12)
                wrapMode: Text.Wrap
            }

            SectionLabel { text: qsTr("Requirements") }
            Repeater {
                model: requirementsModel
                delegate: RowLayout {
                    required property int index
                    required property string text
                    Layout.fillWidth: true
                    spacing: Theme.px(6)
                    Label {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: Theme.px(8)
                        text: "•"
                        color: Theme.subtleText
                    }
                    WrappingField {
                        objectName: "requirementField"
                        spellRanges: dialog.spellRanges
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
                    spacing: Theme.px(6)
                    CheckBox {
                        Layout.alignment: Qt.AlignTop
                        objectName: "criterionCheck"
                        checked: parent.done
                        onToggled: criteriaModel.setProperty(parent.index, "done", checked)
                    }
                    WrappingField {
                        objectName: "criterionField"
                        spellRanges: dialog.spellRanges
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

            SectionLabel { text: qsTr("Artifacts"); visible: !dialog.creating }
            Label {
                objectName: "noArtifacts"
                Layout.fillWidth: true
                visible: !dialog.creating && artifactsModel.count === 0
                text: qsTr("No files attached. You and agents can attach Markdown and images; drop files here or press Ctrl+V.")
                color: Theme.subtleText
                font.pixelSize: Theme.fs(12)
                wrapMode: Text.Wrap
            }
            Repeater {
                model: artifactsModel
                delegate: ColumnLayout {
                    required property string aname
                    required property string akind
                    required property bool byAgent
                    required property string addedBy
                    required property string stage
                    required property string addedAt
                    Layout.fillWidth: true
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(6)

                        Button {
                            objectName: "artifactLink"
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            flat: true
                            text: parent.parent.aname
                            contentItem: Label {
                                text: parent.text
                                elide: Text.ElideRight
                                color: Theme.link
                                font.underline: parent.hovered
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Open in a viewer")
                            onClicked: dialog.artifactClicked(parent.parent.aname)
                        }
                        Label {
                            text: parent.parent.akind === "image" ? qsTr("Image") : qsTr("Markdown")
                            color: Theme.subtleText
                            font.pixelSize: Theme.fs(12)
                        }
                    }
                    Label {
                        objectName: "artifactMeta"
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.px(12)
                        visible: text !== ""
                        text: dialog.artifactMeta(parent.addedBy, parent.byAgent, parent.addedAt, parent.stage)
                        color: Theme.subtleText
                        font.pixelSize: Theme.fs(12)
                        elide: Text.ElideRight
                    }
                }
            }
            Button {
                objectName: "attachButton"
                visible: !dialog.creating
                text: qsTr("Attach file\u2026")
                flat: true
                onClicked: dialog.chooseFile()
            }
            ErrorLabel { objectName: "attachError"; text: dialog.attachError }

            SectionLabel { text: qsTr("References") }
            Label {
                Layout.fillWidth: true
                visible: dialog.creating
                text: qsTr("Save the task first, then reopen it to link it to other tasks.")
                color: Theme.subtleText
                font.pixelSize: Theme.fs(12)
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
                    spacing: Theme.px(6)

                    Label {
                        objectName: "referenceRelation"
                        text: parent.relationLabel
                        color: Theme.subtleText
                        Layout.minimumWidth: Theme.px(100)
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
                            color: Theme.link
                            font.underline: parent.hovered
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Open this task")
                        onClicked: dialog.openTaskRequested(parent.tid)
                    }
                    Label {
                        text: parent.columnTitle
                        color: Theme.subtleText
                        font.pixelSize: Theme.fs(12)
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
                spacing: Theme.px(6)

                ComboBox {
                    id: relationBox
                    objectName: "relationBox"
                    Layout.preferredWidth: Theme.px(140)
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

            ErrorLabel { text: dialog.errorText }
        }
    }

    footerButtons: [
        Button {
            text: qsTr("Delete")
            visible: !dialog.creating
            DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
            onClicked: dialog.deleteRequested(dialog.taskId)
        }
    ]
}
