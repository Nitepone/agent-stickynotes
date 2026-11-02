import QtQuick
import QtQuick.Controls.Fusion
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
    // Decides which notes glow (see GlowTracker); null means none do.
    property var glowTracker: null
    property bool reducedMotion: false
    // Collapsed stacks, as { stackKey: true }. The owner keeps it across board
    // refreshes (this view is rebuilt then) and updates it on stackToggled.
    property var collapsedStacks: ({})
    // View-only filter (TaskFilter) and whether this is the board's last column;
    // null means nothing is hidden.
    property var filter: null
    property bool isLastColumn: false
    // Slim header only (title and count). BoardView ignores it while editing columns.
    property bool collapsed: false
    readonly property var visibleTasks: filter ? filter.visibleTasks(column.tasks, isLastColumn) : column.tasks
    readonly property string countText: filter ? filter.countText(visibleTasks.length, column.tasks.length)
                                               : String(column.tasks.length)
    readonly property bool noMatches: visibleTasks.length === 0 && column.tasks.length > 0
    readonly property bool isColumn: true
    readonly property bool dragging: grip.drag.active

    signal titleClicked()
    signal addTaskClicked()
    signal deleteClicked()
    signal taskClicked(string taskId)
    signal taskDropped(string taskId, int position)
    signal taskMoveRequested(string taskId, int direction)
    signal stackToggled(string stackKey)
    signal collapseToggled()

    StackModel {
        id: stacks
        columnId: root.column.id
        tasks: root.visibleTasks
        allTasks: root.column.tasks
    }

    function isCollapsed(stackKey) {
        return stackKey !== "" && !!collapsedStacks[stackKey]
    }

    // Vertical scroll of the cards, kept across board refreshes (see restoreScroll).
    property alias scrollY: flick.contentY
    ScrollKeeper {
        id: keeper
        flickable: flick
    }

    function maxScrollY() {
        return keeper.maxOffset()
    }

    // Scroll to `y`, clamped to the content.
    function restoreScroll(y) {
        keeper.restore(y)
    }

    objectName: "column-" + column.id
    width: collapsed ? Theme.collapsedColumnWidth : Theme.columnWidth

    // Index among the shown cards at which a task dropped at (x, y) in `item`
    // coordinates lands, ignoring the dragged task itself. Use storedPosition()
    // to turn it into a position in the column's task order.
    function dropIndex(item, x, y, draggedId) {
        const p = item.mapToItem(cards, x, y)
        let index = 0
        for (const card of cardItems(draggedId, true)) {
            if (cardTop(card) + card.height / 2 < p.y)
                index++
        }
        return index
    }

    function storedPosition(index, draggedId) {
        const ids = cardItems(draggedId, true).map(c => c.task.id)
        return storedPositionForShown(ids, index, draggedId)
    }

    // The same for an explicit list of shown card ids (top to bottom, without
    // the dragged one). Hidden (filtered) tasks keep their stored places.
    function storedPositionForShown(shownIds, index, draggedId) {
        return stacks.storedPosition(shownIds, index, draggedId)
    }

    function cardTop(card) {
        return card.mapToItem(cards, 0, 0).y
    }

    // The task cards, top to bottom; with `shownOnly`, without the ones hidden
    // in a collapsed stack.
    function cardItems(excludeId, shownOnly) {
        const result = []
        for (let i = 0; i < cards.children.length; i++) {
            const c = cards.children[i].card
            if (c && c.task.id !== excludeId && (!shownOnly || cards.children[i].visible))
                result.push(c)
        }
        return result
    }

    function headerItems() {
        const result = []
        for (let i = 0; i < cards.children.length; i++) {
            const h = cards.children[i].header
            if (h)
                result.push(h)
        }
        return result
    }

    function indicatorY(index, draggedId) {
        const items = cardItems(draggedId, true)
        if (index < 0 || items.length === 0)
            return 0
        if (index < items.length)
            return cardTop(items[index]) - Theme.cardSpacing / 2 - 1
        const last = items[items.length - 1]
        return cardTop(last) + last.height + Theme.cardSpacing / 2 - 1
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

        // The slim form of a collapsed column.
        Item {
            id: slim
            objectName: "collapsedColumn"
            anchors.fill: parent
            visible: root.collapsed

            ToolButton {
                id: expandButton
                objectName: "expandColumn"
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 6
                text: "›"
                font.pixelSize: 16
                implicitWidth: 32
                implicitHeight: 32
                Accessible.name: qsTr("Expand column %1").arg(root.column.title)
                onClicked: root.collapseToggled()
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Expand column")
            }
            Label {
                id: slimCount
                objectName: "slimCount"
                anchors.top: expandButton.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.countText
                color: Theme.subtleText
                font.pixelSize: 12
            }
            Label {
                objectName: "slimTitle"
                transformOrigin: Item.TopLeft
                rotation: 90
                x: (slim.width + height) / 2
                y: slimCount.y + slimCount.height + 8
                width: Math.max(0, slim.height - y - 8)
                text: root.column.title
                font.pixelSize: 15
                font.bold: true
                color: Theme.text
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            visible: !root.collapsed
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

                FocusLabel {
                    id: titleLabel
                    objectName: "title"
                    Layout.fillWidth: true
                    text: root.column.title
                    font.pixelSize: 15
                    font.bold: true
                    color: Theme.text
                    elide: Text.ElideRight
                    onClicked: root.titleClicked()

                    ToolTip.visible: titleHover.hovered && root.column.description.length > 0
                    ToolTip.text: root.column.description
                    ToolTip.delay: 600
                    HoverHandler { id: titleHover }
                }

                Label {
                    objectName: "count"
                    text: root.countText
                    color: Theme.subtleText
                    font.pixelSize: 13
                }

                ToolButton {
                    objectName: "collapseColumn"
                    visible: !root.editMode
                    text: "‹"
                    font.pixelSize: 16
                    implicitWidth: 28
                    implicitHeight: 28
                    Accessible.name: qsTr("Collapse column %1").arg(root.column.title)
                    onClicked: root.collapseToggled()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Collapse column")
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

            Label {
                objectName: "noMatches"
                visible: root.noMatches
                Layout.fillWidth: true
                text: qsTr("No tasks match the filter.")
                color: Theme.subtleText
                wrapMode: Text.WordWrap
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
                    // Inset so a focused note's ring is not clipped.
                    x: 3
                    width: flick.width - 6
                    spacing: Theme.cardSpacing
                    topPadding: 4

                    Repeater {
                        model: stacks.rows
                        delegate: Item {
                            id: rowItem
                            required property var modelData
                            readonly property bool inStack: modelData.stackKey !== ""
                            readonly property var card: loader.item && loader.item.isTaskCard ? loader.item : null
                            readonly property var header: loader.item && loader.item.isStackHeader ? loader.item : null

                            visible: !(modelData.kind === "card" && root.isCollapsed(modelData.stackKey))
                            width: cards.width
                            height: visible && loader.item ? loader.item.height : 0

                            // A thin rail beside an expanded stack's notes ties them to the
                            // header above; the header itself lines up with plain notes.
                            Rectangle {
                                visible: rowItem.modelData.kind === "card" && rowItem.inStack && rowItem.visible
                                x: 2
                                y: -Theme.cardSpacing
                                width: 3
                                height: rowItem.height + Theme.cardSpacing
                                radius: 1.5
                                color: Theme.stackHeaderBackground
                            }

                            Loader {
                                id: loader
                                x: rowItem.inStack && rowItem.modelData.kind === "card" ? 12 : 0
                                width: rowItem.width - x
                                sourceComponent: rowItem.modelData.kind === "header" ? headerComponent : cardComponent
                            }

                            Component {
                                id: cardComponent
                                TaskCard {
                                    task: rowItem.modelData.task
                                    dragLayer: root.dragLayer
                                    dragEnabled: !root.editMode
                                    showCategory: rowItem.modelData.showCategory
                                    glow: root.glowTracker ? root.glowTracker.intensity(task.id) : 0
                                    glowEdited: root.glowTracker ? root.glowTracker.edited(task.id) : false
                                    reducedMotion: root.reducedMotion
                                    // Only notes near the visible part of the column animate.
                                    glowActive: rowItem.y + height > flick.contentY - 80
                                                && rowItem.y < flick.contentY + flick.height + 80
                                    onClicked: root.taskClicked(task.id)
                                    onMoveRequested: (direction) => root.taskMoveRequested(task.id, direction)
                                }
                            }

                            Component {
                                id: headerComponent
                                StackHeader {
                                    category: rowItem.modelData.category
                                    stackKey: rowItem.modelData.stackKey
                                    count: rowItem.modelData.count
                                    collapsed: root.isCollapsed(rowItem.modelData.stackKey)
                                    reducedMotion: root.reducedMotion
                                    onToggled: root.stackToggled(rowItem.modelData.stackKey)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    parent: flick.contentItem
                    visible: taskDrop.containsDrag && taskDrop.hoverIndex >= 0
                    x: cards.x
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
                    border.color: addButton.visualFocus ? Theme.focusRing : Theme.fieldBorder
                    border.width: addButton.visualFocus ? 2 : 1
                }
                Accessible.name: qsTr("Add a task to %1").arg(root.column.title)
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
            enabled: !root.editMode && !root.collapsed

            property int hoverIndex: -1
            property string draggedId: drag.source ? drag.source.task.id : ""

            onPositionChanged: (event) => hoverIndex = root.dropIndex(taskDrop, event.x, event.y, draggedId)
            onExited: hoverIndex = -1
            onDropped: (event) => {
                const id = event.source.task.id
                const index = root.storedPosition(root.dropIndex(taskDrop, event.x, event.y, id), id)
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
