import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StickyNotes

// One stage of the board. Like TaskCard, the root is a placeholder and the
// visible body is reparented to `dragLayer` while the column is dragged in
// edit mode.
Item {
    id: root

    required property var column        // { id, title, description, tasks }
    required property Item dragLayer
    property bool editMode: false
    readonly property bool isColumn: true
    readonly property bool dragging: grip.drag.active

    signal titleClicked()
    signal addTaskClicked()
    signal deleteClicked()
    signal taskClicked(string taskId)
    signal taskDropped(string taskId, int position)

    objectName: "column-" + column.id
    width: Theme.columnWidth

    // Index at which a task dropped at (x, y) in `item` coordinates lands,
    // ignoring the dragged task itself.
    function dropIndex(item, x, y, draggedId) {
        const p = item.mapToItem(cards, x, y)
        let index = 0
        for (const card of cardItems(draggedId)) {
            if (card.y + card.height / 2 < p.y)
                index++
        }
        return index
    }

    function cardItems(excludeId) {
        const result = []
        for (let i = 0; i < cards.children.length; i++) {
            const c = cards.children[i]
            if (c.isTaskCard && c.task.id !== excludeId)
                result.push(c)
        }
        return result
    }

    function indicatorY(index, draggedId) {
        const items = cardItems(draggedId)
        if (index < 0 || items.length === 0)
            return 0
        if (index < items.length)
            return items[index].y - Theme.cardSpacing / 2 - 1
        const last = items[items.length - 1]
        return last.y + last.height + Theme.cardSpacing / 2 - 1
    }

    Rectangle {
        id: body
        width: root.width
        height: root.height
        anchors.left: root.left
        anchors.top: root.top
        radius: Theme.radius
        color: root.editMode ? Theme.columnEditBackground : Theme.columnBackground
        border.color: taskDrop.containsDrag ? Theme.dropIndicator : "transparent"
        border.width: 2

        Drag.active: grip.drag.active
        Drag.keys: ["column"]
        Drag.source: root
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: 20

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    visible: root.editMode
                    text: "☰"
                    font.pixelSize: 16
                    color: Theme.link

                    MouseArea {
                        id: grip
                        objectName: "grip"
                        anchors.fill: parent
                        anchors.margins: -6
                        preventStealing: true
                        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        drag.target: body
                        drag.threshold: 4
                        onReleased: if (drag.active) body.Drag.drop()
                    }
                }

                Label {
                    id: titleLabel
                    objectName: "title"
                    Layout.fillWidth: true
                    text: root.column.title
                    font.pixelSize: 15
                    font.bold: true
                    color: Theme.text
                    elide: Text.ElideRight

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.titleClicked()
                    }
                    ToolTip.visible: titleHover.hovered && root.column.description.length > 0
                    ToolTip.text: root.column.description
                    ToolTip.delay: 600
                    HoverHandler { id: titleHover }
                }

                Label {
                    text: root.column.tasks.length
                    color: Theme.subtleText
                    font.pixelSize: 13
                }

                ToolButton {
                    visible: root.editMode
                    text: "✕"
                    font.pixelSize: 14
                    implicitWidth: 28
                    implicitHeight: 28
                    onClicked: root.deleteClicked()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Delete column")
                }
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: cards.height + 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: cards
                    width: flick.width
                    spacing: Theme.cardSpacing
                    topPadding: 2

                    Repeater {
                        model: root.column.tasks
                        delegate: TaskCard {
                            required property var modelData
                            task: modelData
                            width: cards.width
                            dragLayer: root.dragLayer
                            dragEnabled: !root.editMode
                            onClicked: root.taskClicked(modelData.id)
                        }
                    }
                }

                Rectangle {
                    parent: flick.contentItem
                    visible: taskDrop.containsDrag && taskDrop.hoverIndex >= 0
                    x: 0
                    y: root.indicatorY(taskDrop.hoverIndex, taskDrop.draggedId)
                    width: cards.width
                    height: 3
                    radius: 1.5
                    color: Theme.dropIndicator
                }
            }

            Button {
                id: addButton
                objectName: "addTask"
                Layout.fillWidth: true
                visible: !root.editMode
                text: "+"
                font.pixelSize: 20
                background: Rectangle {
                    radius: 6
                    color: addButton.down ? Theme.controlDown : addButton.hovered ? Theme.controlHover : "transparent"
                    border.color: Theme.fieldBorder
                }
                onClicked: root.addTaskClicked()
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Add a task to %1").arg(root.column.title)
                ToolTip.delay: 600
            }
        }

        DropArea {
            id: taskDrop
            anchors.fill: parent
            keys: ["task"]
            enabled: !root.editMode

            property int hoverIndex: -1
            property string draggedId: drag.source ? drag.source.task.id : ""

            onPositionChanged: (event) => hoverIndex = root.dropIndex(taskDrop, event.x, event.y, draggedId)
            onExited: hoverIndex = -1
            onDropped: (event) => {
                const id = event.source.task.id
                const index = root.dropIndex(taskDrop, event.x, event.y, id)
                hoverIndex = -1
                event.accept()
                root.taskDropped(id, index)
            }
        }

        states: State {
            when: grip.drag.active
            ParentChange { target: body; parent: root.dragLayer }
            AnchorChanges { target: body; anchors.left: undefined; anchors.top: undefined }
            PropertyChanges { body.opacity: 0.9; body.z: 100 }
        }
    }

    // Slot outline left behind while the column is dragged.
    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: "transparent"
        border.color: Theme.subtleText
        opacity: 0.4
        visible: root.dragging
    }
}
