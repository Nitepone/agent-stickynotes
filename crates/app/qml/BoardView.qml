import QtQuick
import QtQuick.Controls.Fusion
import StickyNotes

// The horizontally scrolling row of columns. Emits user intents; it does not
// talk to the controller itself.
Item {
    id: root

    required property var board         // { title, columns }
    required property Item dragLayer
    property bool editMode: false
    property var glowTracker: null
    property bool reducedMotion: false
    // Which stacks are collapsed, { stackKey: true } (see StackModel). View
    // state only: kept here across board refreshes, never saved.
    property var collapsedStacks: ({})

    // View-only filter (TaskFilter); null shows everything.
    property var filter: null
    // Collapsed columns, { columnId: true }; kept for the session, never saved.
    property var collapsedColumns: ({})

    function toggleColumn(columnId) {
        const next = Object.assign({}, collapsedColumns)
        if (next[columnId])
            delete next[columnId]
        else
            next[columnId] = true
        collapsedColumns = next
    }

    // Escape on a focused card clears the filter.
    Keys.onEscapePressed: (event) => {
        if (filter && filter.active) {
            filter.clear()
            event.accepted = true
        } else {
            event.accepted = false
        }
    }

    function toggleStack(stackKey) {
        const next = Object.assign({}, collapsedStacks)
        if (next[stackKey])
            delete next[stackKey]
        else
            next[stackKey] = true
        collapsedStacks = next
    }

    signal taskClicked(string taskId)
    signal addTaskClicked(var column)
    signal columnTitleClicked(var column)
    signal deleteColumnClicked(var column)
    signal addColumnClicked()
    signal taskMoved(string taskId, string columnId, int position)
    // A whole stack (task ids in order) moved to `columnId` at `position`
    // (an index among that column's tasks without the moved ones).
    signal tasksMoved(var taskIds, string columnId, int position)
    signal columnMoved(string columnId, int position)

    // ---- Keeping the view steady across a board refresh --------------------
    // Columns and cards are updated in place by id, so scroll offsets and focus
    // survive a refresh on their own. scrollState()/restoreScroll() remain as a
    // fallback for an owner that wants to force positions.

    // The task card that has keyboard focus (its id), or the stack header
    // ("stack:" and its key), or "".
    function focusedTaskId() {
        for (const col of columnItems("")) {
            for (const card of col.cardItems("", false)) {
                if (card.activeFocus)
                    return card.task.id
            }
            for (const header of col.headerItems()) {
                if (header.activeFocus)
                    return "stack:" + header.stackKey
            }
        }
        return ""
    }

    function scrollState() {
        const columns = {}
        for (const col of columnItems(""))
            columns[col.column.id] = col.scrollY
        return { x: flick.contentX, columns: columns, focus: focusedTaskId() }
    }

    function restoreScroll(state) {
        keeper.restore(state.x)
        // A column or task that is gone leaves nothing to restore: clamped to 0 / content.
        for (const col of columnItems(""))
            col.restoreScroll(state.columns[col.column.id] || 0)
        if (state.focus !== "") {
            for (const col of columnItems("")) {
                for (const card of col.cardItems("", false)) {
                    if (card.task.id === state.focus)
                        card.forceActiveFocus()
                }
                for (const header of col.headerItems()) {
                    if ("stack:" + header.stackKey === state.focus)
                        header.forceActiveFocus()
                }
            }
        }
    }

    // Ctrl+Left / Ctrl+Right on a focused card: the same move as a drop,
    // into the neighbouring column at the same row (or the end).
    function moveTaskByColumns(taskId, direction) {
        const columns = board.columns
        for (let i = 0; i < columns.length; i++) {
            const index = columns[i].tasks.findIndex(t => t.id === taskId)
            if (index < 0)
                continue
            const target = i + direction
            if (target < 0 || target >= columns.length)
                return
            taskMoved(taskId, columns[target].id, Math.min(index, columns[target].tasks.length))
            return
        }
    }

    // Ctrl+Left / Ctrl+Right on a focused stack header: the whole stack moves
    // one column, to the row of its first task (or the end).
    function moveStackByColumns(taskIds, direction) {
        const columns = board.columns
        for (let i = 0; i < columns.length; i++) {
            const index = columns[i].tasks.findIndex(t => t.id === taskIds[0])
            if (index < 0)
                continue
            const target = i + direction
            if (target < 0 || target >= columns.length)
                return
            tasksMoved(taskIds, columns[target].id, Math.min(index, columns[target].tasks.length))
            return
        }
    }

    function columnItems(excludeId) {
        const result = []
        for (let i = 0; i < row.children.length; i++) {
            const c = row.children[i]
            if (c.isColumn && c.column.id !== excludeId)
                result.push(c)
        }
        return result
    }

    function columnDropIndex(x, draggedId) {
        const p = columnDrop.mapToItem(row, x, 0)
        let index = 0
        for (const c of columnItems(draggedId)) {
            if (c.x + c.width / 2 < p.x)
                index++
        }
        return index
    }

    function indicatorX(index, draggedId) {
        const items = columnItems(draggedId)
        if (index < 0 || items.length === 0)
            return 0
        if (index < items.length)
            return items[index].x - Theme.columnSpacing / 2 - 2
        const last = items[items.length - 1]
        return last.x + last.width + Theme.columnSpacing / 2 - 2
    }

    // Declared below the Flickable so task drops reach the columns first.
    DropArea {
        id: columnDrop
        anchors.fill: parent
        keys: ["column"]

        property int hoverIndex: -1
        property string draggedId: drag.source ? drag.source.column.id : ""

        onPositionChanged: (event) => hoverIndex = root.columnDropIndex(event.x, draggedId)
        onExited: hoverIndex = -1
        onDropped: (event) => {
            const id = event.source.column.id
            const index = root.columnDropIndex(event.x, id)
            hoverIndex = -1
            event.accept()
            root.columnMoved(id, index)
        }
    }

    // The columns as a model keyed by column id, updated in place when `board`
    // changes (see ModelSync), so columns and their cards keep their identity.
    ListModel {
        id: columnModel
        dynamicRoles: true
    }
    ModelSync { id: columnSync }
    function syncColumns() {
        columnSync.sync(columnModel, board.columns, c => c.id)
    }
    onBoardChanged: syncColumns()
    Component.onCompleted: syncColumns()

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: row.width + 32
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

        Row {
            id: row
            x: 16
            y: 16
            height: flick.height - 36
            spacing: Theme.columnSpacing

            Repeater {
                model: columnModel
                delegate: ColumnView {
                    required property var payload
                    required property int index
                    readonly property var modelData: payload
                    column: payload
                    height: row.height
                    dragLayer: root.dragLayer
                    editMode: root.editMode
                    glowTracker: root.glowTracker
                    reducedMotion: root.reducedMotion
                    collapsedStacks: root.collapsedStacks
                    filter: root.filter
                    isLastColumn: index === root.board.columns.length - 1
                    collapsed: !!root.collapsedColumns[modelData.id] && !root.editMode
                    onCollapseToggled: root.toggleColumn(modelData.id)
                    onStackToggled: (stackKey) => root.toggleStack(stackKey)
                    onTitleClicked: root.columnTitleClicked(modelData)
                    onAddTaskClicked: root.addTaskClicked(modelData)
                    onDeleteClicked: root.deleteColumnClicked(modelData)
                    onTaskClicked: (taskId) => root.taskClicked(taskId)
                    onTaskMoveRequested: (taskId, direction) => root.moveTaskByColumns(taskId, direction)
                    onTaskDropped: (taskId, position) => root.taskMoved(taskId, modelData.id, position)
                    onStackDropped: (taskIds, position) => root.tasksMoved(taskIds, modelData.id, position)
                    onStackMoveRequested: (taskIds, direction) => root.moveStackByColumns(taskIds, direction)
                }
            }

            // "Add column" placeholder, edit mode only.
            Rectangle {
                id: addColumn
                objectName: "addColumn"
                visible: root.editMode
                width: Theme.columnWidth
                height: 96
                radius: Theme.radius
                color: addColumnMouse.containsMouse ? Theme.columnEditBackground : "transparent"
                border.color: addColumn.activeFocus ? Theme.focusRing : Theme.secondary
                border.width: 2

                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Add column")
                Accessible.focusable: true
                Accessible.onPressAction: root.addColumnClicked()
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        event.accepted = true
                        root.addColumnClicked()
                    }
                }

                Label {
                    anchors.centerIn: parent
                    text: qsTr("+  Add column")
                    font.pixelSize: 15
                    color: Theme.link
                }
                MouseArea {
                    id: addColumnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.addColumnClicked()
                }
            }
        }

        Rectangle {
            parent: flick.contentItem
            visible: columnDrop.containsDrag && columnDrop.hoverIndex >= 0
            x: row.x + root.indicatorX(columnDrop.hoverIndex, columnDrop.draggedId)
            y: row.y
            width: 4
            height: row.height
            radius: 2
            color: Theme.dropIndicator
        }
    }

    Label {
        anchors.centerIn: parent
        visible: root.board.columns.length === 0 && !root.editMode
        text: qsTr("This board has no columns. Use Board ▸ Edit Columns to add some.")
        color: Theme.subtleText
    }

    // Scroll horizontally while dragging near the left or right edge.
    Timer {
        interval: 30
        repeat: true
        running: root.dragLayer.children.length > 0
        onTriggered: {
            const item = root.dragLayer.children[0]
            const p = item.mapToItem(root, item.width / 2, item.height / 2)
            const edge = 60
            const maxX = Math.max(0, flick.contentWidth - flick.width)
            if (p.x < edge)
                flick.contentX = Math.max(0, flick.contentX - 14)
            else if (p.x > root.width - edge)
                flick.contentX = Math.min(maxX, flick.contentX + 14)
        }
    }

    ScrollKeeper {
        id: keeper
        flickable: flick
        horizontal: true
    }
}
