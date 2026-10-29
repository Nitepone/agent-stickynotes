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

    BoardController { id: controller }

    property var board: ({ title: "", columns: [] })
    property bool editMode: false
    property bool refreshPending: false
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
        if (taskDialog.visible && taskDialog.taskId !== "")
            taskDialog.boardChanged(controller.taskJson(taskDialog.taskId))
    }

    onDraggingChanged: if (!dragging && refreshPending) refresh()
    Component.onCompleted: {
        refresh()
        if (controller.screenshotRequest !== "")
            screenshotTimer.start()
    }

    // Dev aid for headless UI checks: STICKYNOTES_SCREENSHOT=out.png[:scene[:delayMs]]
    // where scene is board (default), edit, task, newtask, column or agent.
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
                else if (scene === "task" && first) boardView.taskClicked(first.tasks[0].id)
                else if (scene === "newtask") taskDialog.openNew(window.board.columns[0])
                else if (scene === "column") columnDialog.openColumn(window.board.columns[0])
                else if (scene === "agent") agentDialog.open()
                start()
                return
            }
            if (!controller.saveScreenshot(path))
                console.warn("screenshot failed:", path)
            Qt.quit()
        }
    }

    Connections {
        target: controller
        function onBoardJsonChanged() { window.refresh() }
    }

    // Parse a controller result; report failures unless the caller handles them.
    function result(json, quiet) {
        const r = JSON.parse(json)
        if (!r.ok && !quiet)
            messageDialog.inform(qsTr("Something went wrong"), r.message)
        return r
    }

    function columnTitle(columnId) {
        for (const c of board.columns)
            if (c.id === columnId) return c.title
        return ""
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
            saveAs(then)
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

    function saveAs(then) {
        saveAsDialog.then = then
        saveAsDialog.open()
    }

    FileDialog {
        id: openDialog
        title: qsTr("Open board")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Board files (*.json)"), qsTr("All files (*)")]
        onAccepted: window.result(controller.openFile(selectedFile))
    }

    FileDialog {
        id: saveAsDialog
        property var then: null
        title: qsTr("Save board as")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [qsTr("Board files (*.json)")]
        onAccepted: {
            const next = then
            then = null
            if (window.result(controller.saveAs(selectedFile)).ok && next)
                next()
        }
        onRejected: then = null
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
        text: qsTr("&New Board")
        shortcut: StandardKey.New
        onTriggered: window.guardUnsaved(() => controller.newBoard())
    }
    Action {
        id: openAction
        text: qsTr("&Open…")
        shortcut: StandardKey.Open
        onTriggered: window.guardUnsaved(() => openDialog.open())
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
                text: qsTr("Save &As…")
                shortcut: StandardKey.SaveAs
                onTriggered: window.saveAs(null)
            }
            Action {
                text: qsTr("&Export to Markdown…")
                shortcut: "Ctrl+E"
                onTriggered: exportDialog.open()
            }
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
        }
        Menu {
            title: qsTr("&Agent")
            MenuItem { action: agentWriteAction }
            MenuSeparator {}
            Action {
                text: qsTr("&Connect Claude Code…")
                onTriggered: agentDialog.open()
            }
        }
    }

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 4

            ToolButton { action: newAction; text: qsTr("New") }
            ToolButton { action: openAction; text: qsTr("Open") }
            ToolButton { action: saveAction; text: qsTr("Save") }
            ToolSeparator {}

            Label {
                Layout.leftMargin: 8
                text: window.board.title
                font.pixelSize: 18
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

            Item { Layout.fillWidth: true }

            Button {
                text: window.editMode ? qsTr("Done editing") : qsTr("Edit columns")
                highlighted: window.editMode
                onClicked: window.editMode = !window.editMode
            }

            // Agent access indicator; click to toggle.
            Rectangle {
                Layout.leftMargin: 8
                implicitWidth: agentLabel.implicitWidth + 24
                implicitHeight: 28
                radius: 14
                color: controller.agentWrite ? Theme.agentReadWrite : Theme.agentReadOnly

                Label {
                    id: agentLabel
                    anchors.centerIn: parent
                    color: "white"
                    font.bold: true
                    font.pixelSize: 12
                    text: controller.agentWrite ? qsTr("Agent: read & write") : qsTr("Agent: read-only")
                }
                MouseArea {
                    id: agentPill
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: controller.setAgentWriteEnabled(!controller.agentWrite)
                }
                ToolTip.visible: agentPill.containsMouse
                ToolTip.text: qsTr("Click to %1 agent write access.\nMCP: %2/mcp")
                              .arg(controller.agentWrite ? qsTr("disable") : qsTr("enable"))
                              .arg(controller.endpoint)
            }
        }
    }

    // ---- Board -----------------------------------------------------------

    BoardView {
        id: boardView
        anchors.fill: parent
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
