import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import StickyNotes

// Application window. This file is the only place that calls the
// BoardController: views below emit intents, and the handlers here turn
// them into controller calls and dialogs.
ApplicationWindow {
    id: window

    width: 1320
    height: 820
    minimumWidth: 640
    minimumHeight: 420
    visible: true
    title: controller.windowTitle + " — Sticky Notes"
    color: Theme.background

    // Standard controls (buttons, menus, text fields, dialogs) take their
    // colors from the palette, so they follow the theme too.
    palette {
        window: Theme.surface
        windowText: Theme.text
        base: Theme.fieldBackground
        alternateBase: Theme.controlBackground
        text: Theme.text
        button: Theme.controlBackground
        buttonText: Theme.text
        highlight: Theme.primary
        highlightedText: Theme.textOnPrimary
        placeholderText: Theme.subtleText
        toolTipBase: Theme.surface
        toolTipText: Theme.text
        link: Theme.link
    }

    // The user's theme settings, from the controller.
    Binding { target: Theme; property: "mode"; value: controller.themeMode }
    Binding { target: Theme; property: "primaryColor"; value: controller.primaryColor }
    Binding { target: Theme; property: "secondaryColor"; value: controller.secondaryColor }
    Binding { target: Theme; property: "noteColor"; value: controller.noteColor }

    BoardController { id: controller }

    property var board: ({ title: "", columns: [] })
    property var linkCandidates: []
    property bool editMode: false
    property bool refreshPending: false
    property bool preferencesOpen: false
    property bool artifactsOpen: false
    // Misspelled words in the task editor, or null with spell check off.
    readonly property var spellRanges: controller.spellCheck
        ? (text) => JSON.parse(controller.misspelledRanges(text)) : null

    // Notes an agent changed glow until the user has been back for a while.
    GlowTracker {
        id: glow
        savedInteraction: controller.lastInteractionMs
    }
    property double lastNotified: 0
    property double lastPersisted: 0

    // The user did something at `when` (ms since the epoch).
    function userInteracted(when) {
        glow.interact(when)
        if (when - lastPersisted > 5000) {
            lastPersisted = when
            controller.recordInteraction(when)
        }
    }
    // Coming back to the window counts. (Not while a dev screenshot run drives
    // the app: there the window is activated at launch, which would hide the
    // difference between input and no input.)
    onActiveChanged: if (active && controller.screenshotRequest === "") userInteracted(Date.now())

    // Input is observed by an event filter in C++ (it cannot be hidden by,
    // or take events from, any view); we poll what it saw.
    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            const when = controller.lastInputMs()
            if (when > window.lastNotified) {
                window.lastNotified = when
                window.userInteracted(when)
            }
        }
    }
    property bool closeConfirmed: false
    readonly property bool dragging: dragLayer.children.length > 0

    // Rebuilding the board destroys delegates, so defer it while a drag is
    // in flight (e.g. an agent edits the board mid-drag).
    function refresh() {
        if (dragging) {
            refreshPending = true
            return
        }
        refreshPending = false
        board = JSON.parse(controller.boardJson)
        linkCandidates = buildLinkCandidates(board)
        glow.sync(board)
        if (taskDialog.visible && taskDialog.taskId !== "")
            taskDialog.boardChanged(controller.taskJson(taskDialog.taskId))
        if (artifactsOpen)
            artifactsPage.artifacts = JSON.parse(controller.artifactsJson())
    }

    onDraggingChanged: if (!dragging && refreshPending) refresh()
    Component.onCompleted: {
        refresh()
        if (controller.screenshotRequest !== "")
            screenshotTimer.start()
        else if (!controller.hasPath)
            Qt.callLater(() => openProjects(false))     // first run: pick a project
    }

    // Dev aid for headless UI checks: STICKYNOTES_SCREENSHOT=out.png[:scene[:delayMs]]
    // where scene is board (default), projects, edit, task, newtask, column, agent, project, prefs, editor, note-demo, theme-demo, theme-reset, interact, synthetic or generate
    // (generate starts a draft for the first task, using settings.json's claude_command).
    Timer {
        id: screenshotTimer
        interval: Number(controller.screenshotRequest.split(":")[2] || 400)
        property bool staged: false
        onTriggered: {
            const [path, scene] = controller.screenshotRequest.split(":")
            if (!staged) {
                staged = true
                const first = window.board.columns.find(c => c.tasks.length > 0)
                if (scene === "edit") window.editMode = true
                else if (scene === "projects") window.openProjects(false)
                else if (scene === "artifacts") window.openArtifactsPage()
                else if (scene === "task" && first) boardView.taskClicked(first.tasks[0].id)
                else if (scene === "newtask") taskDialog.openNew(window.board.columns[0])
                else if (scene === "column") columnDialog.openColumn(window.board.columns[0])
                else if (scene === "agent") agentDialog.open()
                else if (scene === "project") projectDialog.openProject(controller.projectJson())
                else if (scene === "prefs") window.openPreferences()
                else if (scene === "editor") {
                    window.openPreferences()
                    preferencesPage.currentIndex = 1
                }
                else if (scene === "note-demo") {
                    // What the preferences control does, through the real controller.
                    controller.chooseNoteColor(Theme.notePresets[4])
                    window.openPreferences()
                }
                else if (scene === "interact") {
                    // The user does something: glowing notes start to fade.
                    controller.simulateActivity(true)
                } else if (scene === "synthetic") {
                    // Not the user (e.g. Qt re-sending hover after a re-layout): no fade.
                    controller.simulateActivity(false)
                }
                else if (scene === "theme-reset") {
                    controller.resetThemeColors()
                    window.openPreferences()
                }
                else if (scene === "theme-demo") {
                    // What the preferences controls do, through the real controller.
                    controller.chooseThemeMode("dark")
                    controller.choosePrimaryColor(Theme.accentPresets[5])
                    controller.chooseSecondaryColor(Theme.accentPresets[2])
                    window.openPreferences()
                }
                else if (scene === "generate" && first) {
                    boardView.taskClicked(first.tasks[0].id)
                    controller.startGeneration(taskDialog.formJson())
                }
                start()
                return
            }
            if (scene === "interact" || scene === "synthetic" || scene === "board") {
                const ids = []
                for (const c of window.board.columns)
                    for (const t of c.tasks)
                        if (t.agentChange) ids.push("#" + t.number + "=" + glow.intensity(t.id).toFixed(3))
                console.log("GLOW", ids.join(" "))
            }
            if (!controller.saveScreenshot(path))
                console.warn("screenshot failed:", path)
            // Quitting closes the window, which would ask about unsaved changes
            // (the demo board is often "unsaved" after a backfill). Skip that.
            window.closeConfirmed = true
            Qt.quit()
        }
    }

    Connections {
        target: controller
        function onBoardJsonChanged() { window.refresh() }
        function onGenerationFinished(resultJson) {
            const r = JSON.parse(resultJson)
            if (!taskDialog.visible)
                return
            if (r.ok)
                taskDialog.applyDraft(r.requirements, r.criteria)
            else if (r.code !== "cancelled")
                taskDialog.showGenerationError(r.message)
        }
    }

    // Parse a controller result; report failures unless the caller handles them.
    function result(json, quiet) {
        const r = JSON.parse(json)
        if (!r.ok && !quiet)
            messageDialog.inform(qsTr("Something went wrong"), r.message)
        return r
    }

    // Every task, for the "link to another task" picker.
    function buildLinkCandidates(b) {
        const result = []
        for (const column of b.columns)
            for (const task of column.tasks) {
                const text = task.cardText.replace(/\s+/g, " ")
                result.push({
                    id: task.id,
                    columnTitle: column.title,
                    text: text,
                    label: "#" + task.number + "  " + column.title + " \u2014 " + (text.length > 60 ? text.slice(0, 60) + "\u2026" : text),
                })
            }
        return result
    }

    function columnTitle(columnId) {
        for (const c of board.columns)
            if (c.id === columnId) return c.title
        return ""
    }

    function openArtifactsPage() {
        artifactsPage.artifacts = JSON.parse(controller.artifactsJson())
        artifactsPage.now = Date.now()
        artifactsOpen = true
        artifactsPage.forceActiveFocus()
    }

    function openPreferences() {
        preferencesPage.currentIndex = 0          // Personalization first
        artifactsOpen = false
        preferencesOpen = true
        Qt.callLater(preferencesPage.focusSidebar)
    }

    // ---- File handling -------------------------------------------------

    // Run `action` once unsaved changes are saved or discarded.
    function guardUnsaved(action) {
        if (!controller.dirty) {
            action()
            return
        }
        unsavedDialog.pending = action
        unsavedDialog.open()
    }

    function save(then) {
        if (!controller.hasPath) {
            openProjects(true, then)
            return
        }
        const r = result(controller.save(false), true)
        if (r.ok) {
            if (then) then()
        } else if (r.code === "modified_on_disk") {
            messageDialog.ask(qsTr("File changed on disk"),
                              qsTr("The board file was modified by another program since it was opened. Overwrite it with your version?"),
                              qsTr("Overwrite"), true,
                              () => { if (result(controller.save(true)).ok && then) then() })
        } else {
            messageDialog.inform(qsTr("Could not save"), r.message)
        }
    }

    // ---- Artifacts -----------------------------------------------------

    // Each artifact opens in a window of its own, so several can be open
    // side by side while the board stays usable.
    Component {
        id: viewerComponent
        ArtifactViewer {
            styleId: controller.markdownStyle
            onStyleChosen: (id) => controller.chooseMarkdownStyle(id)
            onClosing: Qt.callLater(destroy)
        }
    }

    function openArtifact(name) {
        const r = result(controller.artifactJson(name))
        if (r.ok)
            viewerComponent.createObject(null).showArtifact(r)
    }

    // The project picker. With `forSaving` the board has no project yet and
    // creating one saves it; `then` runs afterwards.
    function openProjects(forSaving, then) {
        projectPicker.then = then || null
        projectPicker.openPicker(controller.projectsJson(), forSaving === true)
    }

    ProjectPicker {
        id: projectPicker
        property var then: null
        onOpenRequested: (dir) => {
            if (window.result(controller.openProject(dir)).ok)
                close()
        }
        onCreateRequested: (name) => {
            if (window.result(controller.newProject(name)).ok) {
                const next = then
                then = null
                close()
                if (next) next()
            }
        }
        onBrowseRequested: projectFolderDialog.open()
    }

    FolderDialog {
        id: projectFolderDialog
        title: qsTr("Choose a project folder (an empty folder becomes a new project)")
        onAccepted: {
            if (window.result(controller.openProjectFolder(selectedFolder)).ok)
                projectPicker.close()
        }
    }

    FileDialog {
        id: skillDialog
        title: qsTr("Export Claude Code skill (save as SKILL.md, e.g. in .claude/skills/stickynotes/)")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "md"
        nameFilters: [qsTr("Skill file (SKILL.md)"), qsTr("Markdown (*.md)")]
        onAccepted: {
            const r = window.result(controller.exportSkill(selectedFile))
            if (r.ok)
                messageDialog.inform(qsTr("Skill exported"),
                                     qsTr("Claude Code loads skills from .claude/skills/<name>/SKILL.md in a project, or ~/.claude/skills/<name>/SKILL.md for all projects. Export again after changing the project settings."))
        }
    }

    FileDialog {
        id: exportDialog
        title: qsTr("Export board to Markdown")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "md"
        nameFilters: [qsTr("Markdown (*.md)")]
        onAccepted: window.result(controller.exportMarkdown(selectedFile))
    }

    onClosing: (close) => {
        controller.recordInteraction(Date.now())
        if (controller.dirty && !closeConfirmed) {
            close.accepted = false
            guardUnsaved(() => {
                closeConfirmed = true
                window.close()
            })
        }
    }

    // ---- Menus and toolbar ---------------------------------------------

    Action {
        id: newAction
        text: qsTr("&New Project…")
        shortcut: StandardKey.New
        onTriggered: window.guardUnsaved(() => window.openProjects(false))
    }
    Action {
        id: openAction
        text: qsTr("&Open Project…")
        shortcut: StandardKey.Open
        onTriggered: window.guardUnsaved(() => window.openProjects(false))
    }
    Action {
        id: preferencesAction
        text: qsTr("&Preferences…")
        shortcut: "Ctrl+,"
        onTriggered: window.openPreferences()
    }
    Action {
        id: saveAction
        text: qsTr("&Save")
        shortcut: StandardKey.Save
        onTriggered: window.save(null)
    }
    Action {
        id: editColumnsAction
        text: qsTr("&Edit Columns")
        checkable: true
        checked: window.editMode
        shortcut: "Ctrl+Shift+E"
        onTriggered: {
            window.editMode = !window.editMode
            checked = Qt.binding(() => window.editMode)
        }
    }
    Action {
        id: agentWriteAction
        text: qsTr("Allow Agent &Write Access")
        checkable: true
        checked: controller.agentWrite
        onTriggered: {
            controller.setAgentWriteEnabled(!controller.agentWrite)
            checked = Qt.binding(() => controller.agentWrite)
        }
    }

    menuBar: MenuBar {
        Menu {
            title: qsTr("&File")
            MenuItem { action: newAction }
            MenuItem { action: openAction }
            MenuSeparator {}
            MenuItem { action: saveAction }
            Action {
                text: qsTr("&Export to Markdown…")
                shortcut: "Ctrl+E"
                onTriggered: exportDialog.open()
            }
            MenuSeparator {}
            MenuItem { action: preferencesAction }
            MenuSeparator {}
            Action {
                text: qsTr("&Quit")
                shortcut: StandardKey.Quit
                onTriggered: window.close()
            }
        }
        Menu {
            title: qsTr("&Board")
            MenuItem { action: editColumnsAction }
            Action {
                text: qsTr("&Rename Board…")
                onTriggered: renameDialog.openWith(window.board.title)
            }
            Action {
                text: qsTr("&Project Settings…")
                onTriggered: projectDialog.openProject(controller.projectJson())
            }
        }
        Menu {
            title: qsTr("&Agent")
            MenuItem { action: agentWriteAction }
            MenuSeparator {}
            Action {
                text: qsTr("&Connect Claude Code…")
                onTriggered: agentDialog.open()
            }
            Action {
                text: qsTr("Export Claude Code &Skill…")
                onTriggered: skillDialog.open()
            }
        }
    }

    // No bar of its own: the title and icons sit on the window background.
    header: ToolBar {
        implicitHeight: 60
        background: Item {}

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 8
            anchors.bottomMargin: 4
            spacing: 8

            Label {
                text: window.board.title
                font.pixelSize: 24
                font.bold: true
                color: Theme.text
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: renameDialog.openWith(window.board.title)
                }
            }
            Label {
                visible: controller.dirty
                text: qsTr("unsaved")
                color: Theme.warning
                font.pixelSize: 12
            }
            // Only there when there is something to save.
            IconButton {
                objectName: "saveButton"
                visible: controller.dirty
                glyph: "save"
                tip: qsTr("Save the board")
                onClicked: window.save(null)
            }

            Item { Layout.fillWidth: true }

            IconButton {
                objectName: "artifactsButton"
                glyph: "folder"
                tip: qsTr("All artifacts in this project")
                checkable: true
                checked: window.artifactsOpen
                onClicked: {
                    if (window.artifactsOpen) window.artifactsOpen = false
                    else window.openArtifactsPage()
                    checked = Qt.binding(() => window.artifactsOpen)
                }
            }
            IconButton {
                objectName: "preferencesButton"
                glyph: "gear"
                tip: qsTr("Preferences")
                onClicked: window.openPreferences()
            }
            IconButton {
                objectName: "editColumnsButton"
                glyph: "pencil"
                tip: window.editMode ? qsTr("Done editing columns") : qsTr("Edit columns")
                checkable: true
                checked: window.editMode
                // The window owns the mode; the button only asks for a change.
                onClicked: {
                    window.editMode = !window.editMode
                    checked = Qt.binding(() => window.editMode)
                }
            }
            // Agent access: green when agents may write, yellow when they may only read.
            IconButton {
                objectName: "agentButton"
                Layout.leftMargin: 4
                glyph: "robot"
                badge: true
                badgeColor: controller.agentWrite ? Theme.agentReadWrite : Theme.agentReadOnly
                badgeGlyphColor: controller.agentWrite ? Theme.textOnAgentReadWrite : Theme.textOnAgentReadOnly
                tip: qsTr("Agent: %1. Click to %2 write access.\nMCP: %3/mcp")
                     .arg(controller.agentWrite ? qsTr("read & write") : qsTr("read-only"))
                     .arg(controller.agentWrite ? qsTr("disable") : qsTr("enable"))
                     .arg(controller.endpoint)
                onClicked: controller.setAgentWriteEnabled(!controller.agentWrite)
            }
        }
    }

    // ---- Board -----------------------------------------------------------

    BoardView {
        id: boardView
        anchors.fill: parent
        enabled: !window.preferencesOpen && !window.artifactsOpen
        glowTracker: glow
        reducedMotion: controller.reduceMotion
        board: window.board
        dragLayer: dragLayer
        editMode: window.editMode

        onTaskClicked: (taskId) => {
            const json = controller.taskJson(taskId)
            if (json !== "")
                taskDialog.openTask(json, window.columnTitle(JSON.parse(json).columnId))
        }
        onAddTaskClicked: (column) => taskDialog.openNew(column)
        onColumnTitleClicked: (column) => columnDialog.openColumn(column)
        onAddColumnClicked: columnDialog.openNew(window.board.columns.length)
        onTaskMoved: (taskId, columnId, position) => window.result(controller.moveTask(taskId, columnId, position))
        onColumnMoved: (columnId, position) => window.result(controller.moveColumn(columnId, position))
        onDeleteColumnClicked: (column) => {
            const n = column.tasks.length
            if (n === 0) {
                window.result(controller.deleteColumn(column.id, false))
                return
            }
            messageDialog.ask(qsTr("Delete column?"),
                              qsTr("The column “%1” contains %n task(s). Deleting the column will also delete them.", "", n).arg(column.title),
                              qsTr("Delete column and tasks"), true,
                              () => window.result(controller.deleteColumn(column.id, true)))
        }
    }

    footer: ToolBar {
        visible: !window.preferencesOpen && !window.artifactsOpen
        implicitHeight: 60

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Label {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                color: window.dragging ? Theme.text : Theme.subtleText
                text: window.dragging && !window.editMode
                      ? qsTr("Drop on a column to move the task, or on the trash can to delete it.")
                      : window.editMode
                        ? qsTr("Editing columns: drag ☰ to reorder, ✕ to delete.")
                        : qsTr("Click a task or column title to edit it. Drag tasks between columns.")
            }

            TrashCan {
                Layout.alignment: Qt.AlignVCenter
                visible: !window.editMode
                dragInProgress: window.dragging
                onTaskDropped: (taskId) => window.confirmDeleteTask(taskId)
            }
        }
    }

    ArtifactsPage {
        id: artifactsPage
        anchors.fill: parent
        visible: window.artifactsOpen
        onBackRequested: window.artifactsOpen = false
        onArtifactClicked: (name) => window.openArtifact(name)
        onTaskClicked: (taskId) => {
            const json = controller.taskJson(taskId)
            taskDialog.openTask(json, window.columnTitle(JSON.parse(json).columnId))
        }
    }

    PreferencesPage {
        id: preferencesPage
        anchors.fill: parent
        visible: window.preferencesOpen
        onBackRequested: window.preferencesOpen = false

        PersonalizationSection {
            themeMode: controller.themeMode
            primaryColor: controller.primaryColor
            secondaryColor: controller.secondaryColor
            onThemeModeChosen: (mode) => controller.chooseThemeMode(mode)
            onPrimaryColorChosen: (color) => controller.choosePrimaryColor(color)
            onSecondaryColorChosen: (color) => controller.chooseSecondaryColor(color)
            onResetColorsRequested: controller.resetThemeColors()
            noteColor: controller.noteColor
            onNoteColorChosen: (color) => controller.chooseNoteColor(color)
            onResetNoteColorRequested: controller.resetNoteColor()
            motionSetting: controller.motionSetting
            onMotionSettingChosen: (setting) => controller.chooseMotionSetting(setting)
        }

        EditorSection {
            spellCheck: controller.spellCheck
            spellAvailable: controller.spellAvailable
            onSpellCheckChosen: (enabled) => controller.chooseSpellCheck(enabled)
            draftAgent: controller.draftAgent
            onDraftAgentChosen: (agent) => controller.chooseDraftAgent(agent)
            draftSystemPrompt: controller.draftSystemPrompt
            onDraftSystemPromptChosen: (prompt) => controller.chooseDraftSystemPrompt(prompt)
            draftModel: controller.draftModel
            onDraftModelChosen: (model) => controller.chooseDraftModel(model)
            draftEffort: controller.draftEffort
            onDraftEffortChosen: (effort) => controller.chooseDraftEffort(effort)
        }
    }

    // Items being dragged are reparented here so they float above everything.
    Item {
        id: dragLayer
        anchors.fill: parent
        z: 20
    }

    function confirmDeleteTask(taskId) {
        const json = controller.taskJson(taskId)
        if (json === "")
            return
        const description = JSON.parse(json).description
        const preview = description.length > 120 ? description.slice(0, 120) + " [...]" : description
        messageDialog.ask(qsTr("Delete task?"),
                          qsTr("Delete this task permanently?\n\n“%1”").arg(preview),
                          qsTr("Delete"), true,
                          () => {
                              if (window.result(controller.deleteTask(taskId)).ok && taskDialog.taskId === taskId)
                                  taskDialog.close()
                          })
    }

    // ---- Dialogs -------------------------------------------------------

    TaskDialog {
        id: taskDialog
        spellRanges: window.spellRanges
        generating: controller.generating
        generatorName: controller.generatorName
        onGenerateRequested: (form) => controller.startGeneration(form)
        onCancelGenerationRequested: controller.cancelGeneration()
        linkCandidates: window.linkCandidates
        relationOptions: JSON.parse(controller.relationOptions())
        onArtifactClicked: (name) => window.openArtifact(name)
        onOpenTaskRequested: (taskId) => {
            const go = () => {
                const json = controller.taskJson(taskId)
                if (json !== "")
                    openTask(json, window.columnTitle(JSON.parse(json).columnId))
            }
            if (isEdited())
                messageDialog.ask(qsTr("Discard changes?"),
                                  qsTr("You have unsaved edits in this task. Open the linked task and discard them?"),
                                  qsTr("Discard and open"), true, go)
            else
                go()
        }
        onSaveRequested: (taskId, columnId, form) => {
            const r = window.result(taskId === "" ? controller.createTask(columnId, form)
                                                  : controller.updateTask(taskId, form), true)
            if (r.ok)
                close()
            else
                errorText = r.message
        }
        onDeleteRequested: (taskId) => window.confirmDeleteTask(taskId)
        onReloadRequested: (taskId) => {
            const json = controller.taskJson(taskId)
            if (json !== "")
                load(JSON.parse(json))
        }
    }

    ColumnDialog {
        id: columnDialog
        onSaveRequested: (columnId, position, title, description) => {
            const r = window.result(columnId === "" ? controller.createColumn(position, title, description)
                                                    : controller.updateColumn(columnId, title, description), true)
            if (r.ok)
                close()
            else
                errorText = r.message
        }
    }

    ConfirmDialog { id: messageDialog }

    ProjectDialog {
        id: projectDialog
        onArtifactClicked: (name) => window.openArtifact(name)
        onSaveRequested: (documentPrompt, codeGuidance) => {
            const r = window.result(controller.updateProject(documentPrompt, codeGuidance), true)
            if (r.ok)
                close()
            else
                errorText = r.message
        }
    }

    Dialog {
        id: unsavedDialog
        property var pending: null
        title: qsTr("Unsaved changes")
        modal: true
        anchors.centerIn: Overlay.overlay
        padding: 16
        standardButtons: Dialog.Save | Dialog.Discard | Dialog.Cancel

        Label { text: qsTr("The board has unsaved changes. Save them first?") }

        onAccepted: {
            const next = pending
            pending = null
            window.save(next)
        }
        onDiscarded: {
            const next = pending
            pending = null
            close()
            if (next) next()
        }
        onRejected: pending = null
    }

    Dialog {
        id: renameDialog
        title: qsTr("Rename board")
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 400
        padding: 16
        standardButtons: Dialog.Save | Dialog.Cancel

        function openWith(title) {
            renameField.text = title
            open()
            renameField.selectAll()
            renameField.forceActiveFocus()
        }

        TextField {
            id: renameField
            anchors.left: parent.left
            anchors.right: parent.right
            onAccepted: renameDialog.accept()
        }
        onAccepted: window.result(controller.renameBoard(renameField.text))
    }

    Dialog {
        id: agentDialog
        title: qsTr("Connect Claude Code")
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(720, window.width - 40)
        padding: 16
        standardButtons: Dialog.Close

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: qsTr("Run this once in a terminal to register the board's MCP server with Claude Code. The server runs while this window is open.")
            }
            TextArea {
                id: setupCommand
                Layout.fillWidth: true
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                font.family: "monospace"
                text: controller.claudeSetupCommand()
            }
            RowLayout {
                Button {
                    text: qsTr("Copy command")
                    onClicked: {
                        setupCommand.selectAll()
                        setupCommand.copy()
                        setupCommand.deselect()
                        copiedLabel.visible = true
                    }
                }
                Label { id: copiedLabel; visible: false; text: qsTr("Copied"); color: Theme.agentReadWrite }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                text: qsTr("REST API: %1/api/v1 (same bearer token)\nAgent write access is currently %2. Toggle it from the Agent menu.")
                      .arg(controller.endpoint)
                      .arg(controller.agentWrite ? qsTr("enabled") : qsTr("disabled"))
            }
        }
        onOpened: copiedLabel.visible = false
    }
}
