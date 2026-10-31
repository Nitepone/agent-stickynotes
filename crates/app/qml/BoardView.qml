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

    signal taskClicked(string taskId)
    signal addTaskClicked(var column)
    signal columnTitleClicked(var column)
    signal deleteColumnClicked(var column)
    signal addColumnClicked()
    signal taskMoved(string taskId, string columnId, int position)
    signal columnMoved(string columnId, int position)

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
                model: root.board.columns
                delegate: ColumnView {
                    required property var modelData
                    column: modelData
                    height: row.height
                    dragLayer: root.dragLayer
                    editMode: root.editMode
                    glowTracker: root.glowTracker
                    reducedMotion: root.reducedMotion
                    onTitleClicked: root.columnTitleClicked(modelData)
                    onAddTaskClicked: root.addTaskClicked(modelData)
                    onDeleteClicked: root.deleteColumnClicked(modelData)
                    onTaskClicked: (taskId) => root.taskClicked(taskId)
                    onTaskDropped: (taskId, position) => root.taskMoved(taskId, modelData.id, position)
                }
            }

            // "Add column" placeholder, edit mode only.
            Rectangle {
                visible: root.editMode
                width: Theme.columnWidth
                height: 96
                radius: Theme.radius
                color: addColumnMouse.containsMouse ? Theme.columnEditBackground : "transparent"
                border.color: Theme.secondary
                border.width: 2

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
}
