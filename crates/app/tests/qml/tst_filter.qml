import QtQuick
import QtTest
import StickyNotes
import TestSupport

// The view-only filter: matching (TaskFilter), what the columns show with it
// (counts, stacks, hint, collapse) and where a drop lands in the stored order.
Item {
    id: scene
    width: 1500
    height: 900

    readonly property real day: 86400000
    readonly property real clock: 1000 * day

    function task(id, number, text, category, ageDays) {
        return { id: id, number: number, cardText: text, searchText: text, done: 0, total: 0,
                 category: category, updatedAt: clock - ageDays * day }
    }

    function sample() {
        return {
            title: "Test",
            categories: ["Backend", "UI"],
            columns: [
                { id: "c0", title: "Backlog", description: "", tasks: [
                    task("t1", 1, "Login page\nrequirement: Use HTTPS", "UI", 1),
                    task("t2", 2, "Fix Cache\ncriterion: Evicts entries", "Backend", 1),
                    task("t3", 3, "Settings page", "UI", 1),
                    task("t4", 4, "Docs", undefined, 1),
                    task("t12", 12, "Another UI note", "ui", 1),
                ] },
                { id: "c1", title: "Done", description: "", tasks: [
                    task("d1", 20, "old one", "UI", 60),
                    task("d2", 21, "recent one", "UI", 2),
                    task("d3", 22, "older still", undefined, 100),
                ] },
            ],
        }
    }

    property var board: sample()

    TaskFilter { id: filter; now: scene.clock }
    GlowTracker { id: tracker }

    BoardView {
        id: boardView
        width: parent.width
        height: parent.height
        board: scene.board
        filter: filter
        dragLayer: dragLayer
        glowTracker: tracker
    }
    Item { id: dragLayer; anchors.fill: parent; z: 10 }

    TestCase {
        name: "Filter"
        when: windowShown

        function init() {
            filter.clear()
            filter.hideOldDone = false
            filter.days = 30
            if (boardView.collapsedColumns["c0"])
                boardView.toggleColumn("c0")
        }

        function ids(tasks) { return tasks.map(t => t.id) }
        function column(id) { return TestHelpers.findByName(boardView, "column-" + id) }

        function test_text_matches_number_and_texts() {
            const tasks = scene.board.columns[0].tasks
            filter.text = "#12"
            compare(ids(filter.visibleTasks(tasks, false)), ["t12"])
            filter.text = "12"
            compare(ids(filter.visibleTasks(tasks, false)), ["t12"])
            filter.text = "https"                      // requirement
            compare(ids(filter.visibleTasks(tasks, false)), ["t1"])
            filter.text = "EVICTS"                     // criterion, any case
            compare(ids(filter.visibleTasks(tasks, false)), ["t2"])
            filter.text = "page"
            compare(ids(filter.visibleTasks(tasks, false)), ["t1", "t3"])
        }

        function test_category_combines_with_text() {
            const tasks = scene.board.columns[0].tasks
            filter.toggleCategory("UI")
            compare(ids(filter.visibleTasks(tasks, false)), ["t1", "t3", "t12"])   // "ui" too
            filter.toggleCategory("Backend")
            compare(ids(filter.visibleTasks(tasks, false)), ["t1", "t2", "t3", "t12"])
            filter.text = "login"
            compare(ids(filter.visibleTasks(tasks, false)), ["t1"])
        }

        function test_counts_and_hint_and_clear() {
            compare(column("c0").countText, "5")
            filter.text = "page"
            compare(column("c0").countText, "2 of 5")
            compare(column("c1").countText, "0 of 3")
            verify(TestHelpers.findByName(column("c1"), "noMatches").visible)
            // Escape on the board clears it.
            boardView.forceActiveFocus()
            keyClick(Qt.Key_Escape)
            compare(filter.text, "")
            compare(column("c0").countText, "5")
            verify(!TestHelpers.findByName(column("c1"), "noMatches").visible)
        }

        function test_stacks_use_visible_tasks_only() {
            const stacks = createTemporaryObject(stackComp, scene)
            stacks.tasks = filter.visibleTasks(scene.board.columns[0].tasks, false)
            compare(stacks.rows.filter(r => r.kind === "header").length, 1)   // UI: t1, t3, t12
            filter.toggleCategory("UI")
            filter.text = "login"
            stacks.tasks = filter.visibleTasks(scene.board.columns[0].tasks, false)
            compare(stacks.rows.filter(r => r.kind === "header").length, 0)   // one visible UI task
            compare(stacks.rows.length, 1)
        }

        function test_collapse_and_expand() {
            const col = column("c0")
            verify(!col.collapsed)
            compare(col.width, Theme.columnWidth)
            mouseClick(TestHelpers.findByName(col, "collapseColumn"))
            verify(col.collapsed)
            compare(col.width, Theme.collapsedColumnWidth)
            verify(TestHelpers.findByName(col, "collapsedColumn").visible)
            mouseClick(TestHelpers.findByName(col, "expandColumn"))
            verify(!col.collapsed)
            compare(col.width, Theme.columnWidth)
        }

        function test_hide_old_done_uses_updated_at() {
            const done = scene.board.columns[1].tasks
            filter.hideOldDone = true
            filter.days = 30
            compare(ids(filter.visibleTasks(done, true)), ["d2"])
            filter.days = 90
            compare(ids(filter.visibleTasks(done, true)), ["d1", "d2"])
            compare(ids(filter.visibleTasks(done, false)), ["d1", "d2", "d3"])   // other columns unaffected
            compare(column("c1").countText, "2 of 3")
        }

        function test_drop_position_is_a_stored_position() {
            filter.text = "page"                      // shows t1, t3; hides t2, t4, t12
            const col = column("c0")
            // Before the second shown card (t3): stored index 2 (t1, t2 come first).
            compare(col.storedPositionForShown(["t1", "t3"], 1, "x"), 2)
            // Past the end of the shown cards: the end of the stored order.
            compare(col.storedPositionForShown(["t1", "t3"], 2, "x"), 5)
            // Dragging t3 itself, dropping before t1: position 0.
            compare(col.storedPositionForShown(["t1"], 0, "t3"), 0)
        }
    }

    Component {
        id: stackComp
        StackModel { columnId: "c0" }
    }
}
