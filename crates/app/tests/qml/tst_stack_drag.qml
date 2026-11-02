import QtQuick
import QtTest
import StickyNotes
import TestSupport

// Dragging a whole stack by its header, with real mouse and key events.
Item {
    id: scene
    width: 1500
    height: 900

    function task(id, number, category) {
        const t = { id: id, number: number, cardText: "task " + id, done: 0, total: 0 }
        if (category !== undefined)
            t.category = category
        return t
    }

    // Backlog: UI stack (t1 t4 t6) and plain t2, t3, t5; Doing: one UI note.
    function sample() {
        return {
            title: "Test",
            categories: ["UI"],
            columns: [
                { id: "c0", title: "Backlog", description: "", tasks: [
                    task("t1", 1, "UI"), task("t2", 2), task("t3", 3),
                    task("t4", 4, "ui"), task("t5", 5), task("t6", 6, "UI"),
                ] },
                { id: "c1", title: "Doing", description: "", tasks: [
                    task("t7", 7, "UI"),
                ] },
            ],
        }
    }

    property var board: sample()

    GlowTracker { id: tracker }

    BoardView {
        id: boardView
        width: parent.width
        height: parent.height - 80
        board: scene.board
        dragLayer: dragLayer
        glowTracker: tracker
    }
    Item { id: dragLayer; anchors.fill: parent; z: 10 }

    SignalSpy { id: stackSpy; target: boardView; signalName: "tasksMoved" }
    SignalSpy { id: taskSpy; target: boardView; signalName: "taskMoved" }

    TestCase {
        name: "StackDrag"
        when: windowShown

        function init() {
            tracker.ticker.running = false
            scene.board = scene.sample()
            boardView.collapsedStacks = ({})
            boardView.reducedMotion = true
            stackSpy.clear()
            taskSpy.clear()
            waitForRendering(boardView)
        }

        function item(name) {
            const found = findChild(boardView, name)
            verify(found, "no item named " + name)
            return found
        }

        function press(source) {
            const from = source.mapToItem(scene, source.width / 2, source.height / 2)
            mousePress(scene, from.x, from.y)
            return from
        }

        function moveTo(from, target, tx, ty, steps) {
            const to = target.mapToItem(scene, tx, ty)
            for (let i = 1; i <= steps; i++)
                mouseMove(scene, from.x + (to.x - from.x) * i / steps, from.y + (to.y - from.y) * i / steps)
            return to
        }

        function dragTo(source, target, tx, ty) {
            const from = press(source)
            const to = moveTo(from, target, tx, ty, 12)
            mouseRelease(scene, to.x, to.y)
        }

        function checkStackDrop(columnId, position) {
            compare(stackSpy.count, 1)
            compare(taskSpy.count, 0)
            compare(stackSpy.signalArguments[0][0], ["t1", "t4", "t6"])
            compare(stackSpy.signalArguments[0][1], columnId)
            compare(stackSpy.signalArguments[0][2], position)
        }

        function test_dragging_an_expanded_header_moves_the_whole_stack() {
            const t7 = item("card-t7")
            dragTo(item("stackHeader-ui"), t7, t7.width / 2, t7.height + 6)
            checkStackDrop("c1", 1)
        }

        function test_dragging_a_collapsed_header_moves_the_whole_stack() {
            boardView.collapsedStacks = ({ "c0\u001fui": true })
            waitForRendering(boardView)
            const t7 = item("card-t7")
            dragTo(item("stackHeader-ui"), t7, t7.width / 2, -6)
            checkStackDrop("c1", 0)
        }

        function test_dropping_within_the_column_reports_a_position_without_the_stack() {
            // Without t1 t4 t6 the column is t2 t3 t5; well below t5 is the end, 3.
            // (The ghost trails the synthetic pointer by about one step, hence the margin.)
            const t5 = item("card-t5")
            dragTo(item("stackHeader-ui"), t5, t5.width / 2, t5.height + 50)
            checkStackDrop("c0", 3)
        }

        function test_escape_cancels_the_drag() {
            const t7 = item("card-t7")
            const from = press(item("stackHeader-ui"))
            const to = moveTo(from, t7, t7.width / 2, t7.height + 6, 12)
            keyClick(Qt.Key_Escape)
            mouseMove(scene, to.x, to.y + 4)
            mouseRelease(scene, to.x, to.y + 4)
            compare(stackSpy.count, 0)
            compare(taskSpy.count, 0)
        }

        function test_dropping_outside_any_column_changes_nothing() {
            const header = item("stackHeader-ui")
            const from = press(header)
            mouseMove(scene, from.x + 40, from.y + 20)
            mouseMove(scene, from.x + 80, scene.height - 20)
            mouseRelease(scene, from.x + 80, scene.height - 20)
            compare(stackSpy.count, 0)
            compare(taskSpy.count, 0)
        }

        function test_ctrl_right_on_a_focused_header_moves_the_stack_one_column() {
            const header = item("stackHeader-ui")
            header.forceActiveFocus()
            keyClick(Qt.Key_Right, Qt.ControlModifier)
            compare(stackSpy.count, 1)
            compare(stackSpy.signalArguments[0][0], ["t1", "t4", "t6"])
            compare(stackSpy.signalArguments[0][1], "c1")
            compare(stackSpy.signalArguments[0][2], 0)
            keyClick(Qt.Key_Left, Qt.ControlModifier)       // already in the first column
            compare(stackSpy.count, 1)
        }

        function test_a_card_inside_an_expanded_stack_still_moves_alone() {
            const t7 = item("card-t7")
            dragTo(item("card-t4"), t7, t7.width / 2, t7.height + 6)
            compare(stackSpy.count, 0)
            compare(taskSpy.count, 1)
            compare(taskSpy.signalArguments[0][0], "t4")
            compare(taskSpy.signalArguments[0][1], "c1")
        }

        function test_a_click_on_the_header_still_toggles() {
            mouseClick(item("stackHeader-ui"))
            compare(boardView.collapsedStacks["c0\u001fui"], true)
            compare(stackSpy.count, 0)
        }
    }
}
