import QtQuick
import QtQuick.Controls.Fusion
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
    minimumWidth: Theme.px(640)
    minimumHeight: Theme.px(420)
    visible: true
    font.pointSize: Theme.basePointSize * Theme.scale
    title: controller.windowTitle
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
        // Fusion draws bevels, outlines and scroll bar handles from these.
        light: Theme.shadeLight
        midlight: Theme.shadeMidlight
        mid: Theme.shadeMid
        dark: Theme.shadeDark
        shadow: Theme.shadeShadow
    }

    // Tell Qt the color scheme too, so what the platform draws itself (the
    // Windows title bar, native dialogs) matches instead of following the
    // system setting. Needs Qt 6.8.
    Binding { target: Qt.styleHints; property: "colorScheme"; value: Theme.dark ? Qt.Dark : Qt.Light }

    // The user's theme settings, from the controller.
    Binding { target: Theme; property: "mode"; value: prefs.theme_mode }
    Binding { target: Theme; property: "scale"; value: prefs.ui_scale }
    Binding { target: Theme; property: "primaryColor"; value: prefs.primary_color }
    Binding { target: Theme; property: "secondaryColor"; value: prefs.secondary_color }
    Binding { target: Theme; property: "noteColor"; value: prefs.note_color }
    Binding { target: Theme; property: "noteStyle"; value: prefs.note_style }
    Binding { target: Theme; property: "notePalette"; value: prefs.note_palette }
    Binding { target: Theme; property: "noteCategories"; value: window.board.categories || [] }

    BoardController { id: controller }
    // The user's preferences (see settings::PREFS); replaced whenever one changes.
    readonly property var prefs: JSON.parse(controller.prefsJson)
    function resetThemeColors() {
        controller.choosePref("primary_color", "")
        controller.choosePref("secondary_color", "")
    }

    property var board: ({ title: "", columns: [] })
    property var linkCandidates: []
    property bool editMode: false
    property bool refreshPending: false
    property bool preferencesOpen: false
    property bool artifactsOpen: false
    // Artifact viewer windows showing; they own Ctrl+= / Ctrl+- / Ctrl+0 meanwhile.
    property int viewersOpen: 0
    // Misspelled words in the task editor, or null with spell check off.
    readonly property var spellRanges: prefs.spell_check
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
        // BoardView updates its columns and cards in place by id, so scroll
        // positions, focus and hover need no saving and restoring.
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

    // Dev aid for headless UI checks: STICKYNOTES_SCREENSHOT=out.png[:scene[:delayMs[:WxH]]]
    // where scene is board (default), projects, edit, task, newtask, collapsed, column, agent, project, prefs, editor, note-demo, theme-demo, theme-reset, interact, synthetic or generate
    // (generate starts a draft for the first task, using settings.json's claude_command).
    Timer {
        id: screenshotTimer
        interval: Number(controller.screenshotRequest.split(":")[2] || 400)
        property bool staged: false
        onTriggered: {
            const [path, scene] = controller.screenshotRequest.split(":")
            if (!staged) {
                staged = true
                const size = (controller.screenshotRequest.split(":")[3] || "").split("x")
                if (size.length === 2 && size[0] > 0 && size[1] > 0) {
                    window.width = Number(size[0])
                    window.height = Number(size[1])
                }
                const first = window.board.columns.find(c => c.tasks.length > 0)
                if (scene === "edit") window.editMode = true
                else if (scene === "projects") window.openProjects(false)
                else if (scene === "artifacts") window.openArtifactsPage()
                else if (scene === "task" && first) boardView.taskClicked(first.tasks[0].id)
                else if (scene === "collapsed") {
                    // Collapse every stack, as a click on each header would.
                    for (const column of window.board.columns) {
                        const counts = {}
                        for (const t of column.tasks) {
                            const key = (t.category || "").trim().toLowerCase()
                            if (key !== "")
                                counts[key] = (counts[key] || 0) + 1
                        }
                        for (const key in counts)
                            if (counts[key] > 1)
                                boardView.toggleStack(column.id + "\u001f" + key)
                    }
                }
                else if (scene === "newtask") taskDialog.openNew(window.board.columns[0])
                else if (scene === "column") columnDialog.openColumn(window.board.columns[0])
                else if (scene === "agent" || scene === "agent-all") {
                    agentDialog.open()
                    if (scene === "agent-all") agentDialog.expandAll()
                }
                else if (scene === "project") projectDialog.openProject(controller.projectJson())
                else if (scene === "prefs") window.openPreferences()
                else if (scene === "editor") {
                    window.openPreferences()
                    preferencesPage.currentIndex = 1
                }
                else if (scene === "note-demo") {
                    // What the preferences control does, through the real controller.
                    controller.choosePref("note_color", Theme.notePresets[4])
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
                    resetThemeColors()
                    window.openPreferences()
                }
                else if (scene === "theme-demo") {
                    // What the preferences controls do, through the real controller.
                    controller.choosePref("theme_mode", "dark")
                    controller.choosePref("primary_color", Theme.accentPresets[5])
                    controller.choosePref("secondary_color", Theme.accentPresets[2])
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
                taskDialog.applyDraft(r.requirements, r.criteria, r.category, r.categoryInvalid)
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

    // Open the task dialog on a task's JSON (empty when the task is gone).
    function openTaskFromJson(json) {
        if (json !== "")
            taskDialog.openTask(json, window.columnTitle(JSON.parse(json).columnId))
    }

    // Close a form dialog when its save succeeded, otherwise show the error in it.
    function finishSave(dialog, resultJson) {
        const r = result(resultJson, true)
        if (r.ok)
            dialog.close()
        else
            dialog.errorText = r.message
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
            const notice = controller.takeBackupNotice()
            if (notice !== "")
                messageDialog.inform(qsTr("Backup problem"), notice)
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
            styleId: prefs.markdown_style
            onStyleChosen: (id) => controller.choosePref("markdown_style", id)
            onVisibleChanged: window.viewersOpen += visible ? 1 : -1
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

    // View-only filter of the board (never saved, never seen by agents).
    TaskFilter { id: taskFilter }
    Shortcut {
        sequences: [StandardKey.Find]
        enabled: !window.preferencesOpen && !window.artifactsOpen
        onActivated: filterBar.focusField()
    }

    ZoomActions {
        id: zoom
        current: Theme.scale
        active: window.viewersOpen === 0
        onScaleRequested: (value) => controller.choosePref("ui_scale", String(value))
    }

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

    // Ctrl+Z and Ctrl+Shift+Z belong to a focused text field, not the board.
    readonly property bool textFieldFocused: window.activeFocusItem
        && (window.activeFocusItem instanceof TextInput
            || window.activeFocusItem instanceof TextEdit)

    Action {
        id: undoAction
        text: controller.undoLabel === "" ? qsTr("&Undo") : qsTr("&Undo %1").arg(controller.undoLabel)
        enabled: controller.undoLabel !== ""
        shortcut: "Ctrl+Z"
        onTriggered: window.result(controller.undo(), false)
    }
    Action {
        id: redoAction
        text: controller.redoLabel === "" ? qsTr("&Redo") : qsTr("&Redo %1").arg(controller.redoLabel)
        enabled: controller.redoLabel !== ""
        shortcut: "Ctrl+Shift+Z"
        onTriggered: window.result(controller.redo(), false)
    }
    Shortcut {
        sequences: ["Ctrl+Y"]
        enabled: !window.textFieldFocused && controller.redoLabel !== ""
        onActivated: redoAction.trigger()
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
            MenuItem { action: undoAction }
            MenuItem { action: redoAction }
            MenuSeparator {}
            Action {
                text: qsTr("Restore from &Backup…")
                enabled: controller.hasPath
                onTriggered: restoreDialog.openWith(controller.backupsJson())
            }
            MenuItem { action: editColumnsAction }
            Action {
                text: qsTr("&Project Settings…")
                onTriggered: projectDialog.openProject(controller.projectJson())
            }
        }
        Menu {
            title: qsTr("&View")
            MenuItem { action: zoom.zoomInAction }
            MenuItem { action: zoom.zoomOutAction }
            MenuItem { action: zoom.actualSizeAction }
        }
        Menu {
            title: qsTr("&Agent")
            MenuItem { action: agentWriteAction }
            MenuSeparator {}
            Action {
                text: qsTr("&Connect Agent…")
                onTriggered: agentDialog.open()
            }
            Action {
                text: qsTr("&Activity…")
                onTriggered: {
                    activityDialog.activityJson = controller.activityJson()
                    activityDialog.open()
                }
            }
            Action {
                text: qsTr("Export Claude Code &Skill…")
                onTriggered: skillDialog.open()
            }
        }
    }

    // No bar of its own: the title and icons sit on the window background.
    header: ToolBar {
        implicitHeight: Theme.px(60)
        background: Item {}

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.px(16)
            anchors.rightMargin: Theme.px(16)
            anchors.topMargin: Theme.px(8)
            anchors.bottomMargin: Theme.px(4)
            spacing: Theme.px(8)

            FocusLabel {
                objectName: "boardTitle"
                text: window.board.title
                accessibleName: qsTr("Board title: %1. Project settings").arg(window.board.title)
                font.pixelSize: Theme.fs(24)
                font.bold: true
                onClicked: projectDialog.openProject(controller.projectJson(), true)
            }
            Label {
                visible: controller.dirty
                text: qsTr("unsaved")
                color: Theme.warning
                font.pixelSize: Theme.fs(12)
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

            FilterBar {
                id: filterBar
                visible: !window.preferencesOpen && !window.artifactsOpen
                filter: taskFilter
                categories: window.board.categories || []
                lastColumnTitle: window.board.columns.length > 0
                                 ? window.board.columns[window.board.columns.length - 1].title : ""
            }

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
                Layout.leftMargin: Theme.px(4)
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
        filter: taskFilter
        reducedMotion: prefs.reduce_motion
        board: window.board
        dragLayer: dragLayer
        editMode: window.editMode

        onTaskClicked: (taskId) => {
            window.openTaskFromJson(controller.taskJson(taskId))
        }
        onAddTaskClicked: (column) => taskDialog.openNew(column)
        onColumnTitleClicked: (column) => columnDialog.openColumn(column)
        onAddColumnClicked: columnDialog.openNew(window.board.columns.length)
        onTaskMoved: (taskId, columnId, position) => window.result(controller.moveTask(taskId, columnId, position))
        onTasksMoved: (taskIds, columnId, position) => window.result(controller.moveTasks(JSON.stringify(taskIds), columnId, position))
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

    footer: BottomBar {
        visible: prefs.show_bottom_bar && !window.preferencesOpen && !window.artifactsOpen
        dragging: window.dragging
        editMode: window.editMode
        onTaskDropped: (taskId) => window.confirmDeleteTask(taskId)
    }

    // With the bottom bar hidden the trash can floats over the board's corner
    // while a task is dragged. Below the drag layer, above the board.
    FloatingTrash {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.px(20)
        z: 10
        barShown: prefs.show_bottom_bar
        dragging: window.dragging && !window.preferencesOpen && !window.artifactsOpen
        editMode: window.editMode
        onTaskDropped: (taskId) => window.confirmDeleteTask(taskId)
    }

    ArtifactsPage {
        id: artifactsPage
        anchors.fill: parent
        visible: window.artifactsOpen
        onBackRequested: window.artifactsOpen = false
        onArtifactClicked: (name) => window.openArtifact(name)
        onTaskClicked: (taskId) => {
            window.openTaskFromJson(controller.taskJson(taskId))
        }
    }

    PreferencesPage {
        id: preferencesPage
        anchors.fill: parent
        visible: window.preferencesOpen
        onBackRequested: window.preferencesOpen = false

        PersonalizationSection {
            themeMode: prefs.theme_mode
            primaryColor: prefs.primary_color
            secondaryColor: prefs.secondary_color
            onThemeModeChosen: (mode) => controller.choosePref("theme_mode", mode)
            onPrimaryColorChosen: (color) => controller.choosePref("primary_color", color)
            onSecondaryColorChosen: (color) => controller.choosePref("secondary_color", color)
            onResetColorsRequested: resetThemeColors()
            noteColor: prefs.note_color
            onNoteColorChosen: (color) => controller.choosePref("note_color", color)
            onResetNoteColorRequested: controller.choosePref("note_color", "")
            noteStyle: prefs.note_style
            notePalette: prefs.note_palette
            onNoteStyleChosen: (style) => controller.choosePref("note_style", style)
            onNotePaletteChosen: (id) => controller.choosePref("note_palette", id)
            motionSetting: prefs.motion_setting
            onMotionSettingChosen: (setting) => controller.choosePref("motion_setting", setting)
            showBottomBar: prefs.show_bottom_bar
            onShowBottomBarChosen: (shown) => controller.choosePref("show_bottom_bar", String(shown))
        }

        EditorSection {
            id: editorSection
            spellCheck: prefs.spell_check
            spellAvailable: controller.spellAvailable
            onSpellCheckChosen: (enabled) => controller.choosePref("spell_check", String(enabled))
            draftAgent: prefs.draft_agent
            onDraftAgentChosen: (agent) => controller.choosePref("draft_agent", agent)
            draftSystemPrompt: prefs.draft_system_prompt
            onDraftSystemPromptChosen: (prompt) => controller.choosePref("draft_system_prompt", prompt)
            draftModel: prefs.draft_model
            onDraftModelChosen: (model) => controller.choosePref("draft_model", model)
            draftEffort: prefs.draft_effort
            onDraftEffortChosen: (effort) => controller.choosePref("draft_effort", effort)
            ollamaEndpoint: prefs.ollama_endpoint
            onOllamaEndpointChosen: (endpoint) => ollamaEndpointInvalid = !controller.choosePref("ollama_endpoint", endpoint)
            ollamaToken: prefs.ollama_token
            onOllamaTokenChosen: (token) => controller.choosePref("ollama_token", token)
            onTestConnectionRequested: controller.checkOllamaConnection()
        }

        AboutSection {
            version: controller.appVersion
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
        onUndoDraftRequested: messageDialog.ask(
            qsTr("Undo the draft?"),
            qsTr("Remove the drafted requirements and criteria, and put the requirements, criteria and category back as they were before the draft? This also discards any changes you made to them since."),
            qsTr("Undo draft"), true, () => taskDialog.undoDraft())
        linkCandidates: window.linkCandidates
        categories: window.board.categories || []
        relationOptions: JSON.parse(controller.relationOptions())
        onArtifactClicked: (name) => window.openArtifact(name)
        onAttachRequested: (taskId, fileUrl) => {
            const r = window.result(controller.attachArtifact(taskId, fileUrl), true)
            if (!r.ok)
                attachFailed(r.message)
            artifactsAttached(controller.taskJson(taskId))
        }
        onPasteRequested: (taskId) => {
            const r = window.result(controller.attachClipboard(taskId), true)
            if (!r.ok)
                attachFailed(r.message)
            artifactsAttached(controller.taskJson(taskId))
        }
        onOpenTaskRequested: (taskId) => {
            const go = () => window.openTaskFromJson(controller.taskJson(taskId))
            if (isEdited())
                messageDialog.ask(qsTr("Discard changes?"),
                                  qsTr("You have unsaved edits in this task. Open the linked task and discard them?"),
                                  qsTr("Discard and open"), true, go)
            else
                go()
        }
        onSaveRequested: (taskId, columnId, form) => window.finishSave(taskDialog,
            taskId === "" ? controller.createTask(columnId, form) : controller.updateTask(taskId, form))
        onDeleteRequested: (taskId) => window.confirmDeleteTask(taskId)
        onReloadRequested: (taskId) => {
            const json = controller.taskJson(taskId)
            if (json !== "")
                load(JSON.parse(json))
        }
    }

    ColumnDialog {
        id: columnDialog
        onSaveRequested: (columnId, position, title, description) => window.finishSave(columnDialog,
            columnId === "" ? controller.createColumn(position, title, description)
                            : controller.updateColumn(columnId, title, description))
    }

    ConfirmDialog { id: messageDialog }
    RestoreDialog {
        id: restoreDialog
        onRestoreRequested: (name) => window.result(controller.restoreBackup(name), false)
    }

    ProjectDialog {
        id: projectDialog
        onArtifactClicked: (name) => window.openArtifact(name)
        onSaveRequested: (title, documentPrompt, codeGuidance) =>
            window.finishSave(projectDialog,
                              controller.updateProject(title, documentPrompt, codeGuidance))
    }

    UnsavedDialog {
        id: unsavedDialog
        onSaveRequested: (next) => window.save(next)
        onDiscardRequested: (next) => { if (next) next() }
    }

    ActivityDialog { id: activityDialog }

    AgentConnectDialog {
        id: agentDialog
        setupCommand: controller.claudeSetupCommand()
        desktopProjectJson: agentSetup.desktop_project
        desktopBridgeJson: agentSetup.desktop_bridge
        opencodeJson: agentSetup.opencode
        endpoint: controller.endpoint
        agentWrite: controller.agentWrite
        reducedMotion: prefs.reduce_motion
        onTestRequested: (client) => controller.checkAgentConnection(client)
    }
    readonly property var agentSetup: JSON.parse(controller.agentSetupJson())
    Connections {
        target: controller
        function onOllamaCheckFinished(resultJson) {
            const r = JSON.parse(resultJson)
            editorSection.setTestResult(r.ok, r.note, r.message)
        }
        function onAgentCheckFinished(client, resultJson) {
            const r = JSON.parse(resultJson)
            agentDialog.setCheckResult(client, r.ok, r.message)
        }
    }
}
