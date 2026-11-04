import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

// The bottom bar and the floating trash can used when it is hidden. Wired
// as Main.qml does: the bar is the window footer, the floating trash can sits
// over the board's corner, and a drag is "a child in the drag layer".
Item {
    id: scene
    width: 1500
    height: 800

    property bool barShown: true
    property bool editMode: false
    readonly property bool dragging: dragLayer.children.length > 0

    readonly property var board: TestHelpers.sampleBoard({})

    GlowTracker { id: tracker }

    // Stands in for the window: footer below, board filling the rest.
    Item {
        id: win
        anchors.fill: parent

        BottomBar {
            id: bar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: visible ? implicitHeight : 0
            visible: scene.barShown
            dragging: scene.dragging
            editMode: scene.editMode
            onTaskDropped: (taskId) => dropSpy.record(taskId)
        }

        BoardView {
            id: boardView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: bar.visible ? bar.top : parent.bottom
            board: scene.board
            dragLayer: dragLayer
            glowTracker: tracker
            editMode: scene.editMode
        }

        FloatingTrash {
            id: floating
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.px(20)
            z: 10
            barShown: scene.barShown
            dragging: scene.dragging
            editMode: scene.editMode
            onTaskDropped: (taskId) => dropSpy.record(taskId)
        }

        Item { id: dragLayer; anchors.fill: parent; z: 20 }
    }

    QtObject {
        id: dropSpy
        property var dropped: []
        function record(id) { dropped = dropped.concat([id]) }
    }

    TestCase {
        name: "BottomBar"
        when: windowShown

        function init() {
            Theme.scale = 1
            scene.barShown = true
            scene.editMode = false
            dropSpy.dropped = []
            tracker.ticker.running = false
        }
        function cleanup() { Theme.scale = 1 }

        function card(id) {
            const c = findChild(boardView, "card-" + id)
            verify(c, "card " + id)
            return c
        }
        function trashCan() { return findChild(floating, "floatingTrashCan") }

        // Press a card and move a little: the drag is under way, not released.
        function startDrag(c) {
            const from = c.mapToItem(scene, c.width / 2, c.height / 2)
            mousePress(scene, from.x, from.y)
            for (let i = 1; i <= 6; i++)
                mouseMove(scene, from.x + i * 10, from.y + i * 10)
            return from
        }
        function dragOntoFloatingTrash(c) {
            startDrag(c)
            tryVerify(() => scene.dragging)
            const to = floating.mapToItem(scene, floating.width / 2, floating.height / 2)
            mouseMove(scene, to.x, to.y)
            mouseRelease(scene, to.x, to.y)
        }

        function test_bar_shows_hint_and_gives_board_the_rest() {
            verify(bar.visible)
            compare(bar.height, Theme.px(60))
            verify(findChild(bar, "barHint").visible)
            compare(boardView.height, scene.height - Theme.px(60))
        }

        function test_hidden_bar_frees_its_height_for_the_board() {
            const before = boardView.height
            scene.barShown = false
            verify(!bar.visible)
            verify(!findChild(bar, "barHint").visible)
            compare(boardView.height, before + Theme.px(60))
            scene.barShown = true
            compare(boardView.height, before)
        }

        function test_layout_holds_at_the_scale_limits() {
            for (const s of [0.7, 2.0]) {
                Theme.scale = s
                scene.barShown = true
                compare(bar.height, Theme.px(60))
                compare(boardView.height, scene.height - Theme.px(60))
                compare(boardView.y + boardView.height, bar.y)
                scene.barShown = false
                compare(boardView.height, scene.height)
                verify(floating.width > 0 && floating.height > 0)
            }
        }

        function test_floating_trash_is_hidden_while_the_bar_is_shown() {
            startDrag(card("t0"))
            tryVerify(() => scene.dragging)
            verify(!floating.visible)
            verify(findChild(bar, "barTrash").visible)
            mouseRelease(scene, 700, 700)
        }

        function test_floating_trash_appears_only_during_a_drag() {
            scene.barShown = false
            verify(!floating.visible, "not at rest")
            startDrag(card("t0"))
            tryVerify(() => scene.dragging)
            verify(floating.visible, "during the drag")
            // Small: it leaves most of the board uncovered.
            verify(floating.width * floating.height < scene.width * scene.height / 50)
            mouseRelease(scene, 700, 700)   // dropped on empty board space
            tryVerify(() => !scene.dragging)
            verify(!floating.visible, "gone when the drag ends")
        }

        function test_dropping_on_the_floating_trash_deletes_through_the_same_signal() {
            scene.barShown = false
            dragOntoFloatingTrash(card("t2"))
            compare(dropSpy.dropped.length, 1)
            compare(dropSpy.dropped[0], "t2")
            tryVerify(() => !floating.visible)
        }

        function test_no_floating_trash_while_editing_columns() {
            scene.barShown = false
            scene.editMode = true
            verify(!floating.visible)
            scene.editMode = false
            verify(!floating.visible)
        }

        function test_a_drag_that_is_cancelled_hides_it_again() {
            scene.barShown = false
            const from = startDrag(card("t0"))
            tryVerify(() => floating.visible)
            // Cancel the way the drag layer does: the dragged card goes away.
            for (let i = dragLayer.children.length - 1; i >= 0; i--)
                dragLayer.children[i].parent = null
            tryVerify(() => !floating.visible)
            mouseRelease(scene, from.x, from.y)
            compare(dropSpy.dropped.length, 0)
        }
    }
}
