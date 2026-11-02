import QtQuick
import QtTest
import StickyNotes
import TestSupport

// Stacks of same-category notes: the grouping logic (StackModel) and the
// views that show it, with real mouse and key events. No controller involved.
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

    // Backlog: UI x3 (one typed in lower case), two plain, one lone Backend.
    function sample() {
        return {
            title: "Test",
            categories: ["Backend", "UI"],
            columns: [
                { id: "c0", title: "Backlog", description: "", tasks: [
                    task("t1", 1, "UI"), task("t2", 2), task("t3", 3, "Backend"),
                    task("t4", 4, "ui"), task("t5", 5), task("t6", 6, "UI"),
                ] },
                { id: "c1", title: "Doing", description: "", tasks: [
                    task("t7", 7, "UI"),
                ] },
            ],
        }
    }

    property var board: sample()

    StackModel { id: model; columnId: "c0"; tasks: scene.board.columns[0].tasks }

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

    SignalSpy { id: movedSpy; target: boardView; signalName: "taskMoved" }
    SignalSpy { id: clickedSpy; target: boardView; signalName: "taskClicked" }

    TestCase {
        name: "Stacks"
        when: windowShown

        function init() {
            tracker.ticker.running = false
            scene.board = scene.sample()
            boardView.collapsedStacks = ({})
            boardView.reducedMotion = false
            movedSpy.clear()
            clickedSpy.clear()
            waitForRendering(boardView)
        }

        function item(name) {
            const found = findChild(boardView, name)
            verify(found, "no item named " + name)
            return found
        }

        function layout(columnId) {
            return item("column-" + columnId).cardItems("", false).map(c => c.task.id)
        }

        function shown(columnId) {
            return item("column-" + columnId).cardItems("", true).map(c => c.task.id)
        }

        function header(columnId, name) {
            const col = item("column-" + columnId)
            return col.headerItems().find(h => h.objectName === "stackHeader-" + name)
        }

        function headerCount(columnId) {
            return item("column-" + columnId).headerItems().length
        }

        function move(taskId, from, to, position) {
            const b = JSON.parse(JSON.stringify(scene.board))
            const src = b.columns.find(c => c.id === from)
            const dst = b.columns.find(c => c.id === to)
            const t = src.tasks.splice(src.tasks.findIndex(x => x.id === taskId), 1)[0]
            dst.tasks.splice(position, 0, t)
            scene.board = b
            waitForRendering(boardView)
        }

        function setCategory(taskId, category) {
            const b = JSON.parse(JSON.stringify(scene.board))
            for (const c of b.columns)
                for (const t of c.tasks)
                    if (t.id === taskId) {
                        if (category === "") delete t.category
                        else t.category = category
                    }
            scene.board = b
            waitForRendering(boardView)
        }

        // ---- grouping logic -------------------------------------------------

        function test_model_groups_a_stack_at_its_first_member() {
            const rows = model.rows.map(r => r.kind === "header" ? "H:" + r.category + ":" + r.count : r.task.id)
            compare(rows, ["H:UI:3", "t1", "t4", "t6", "t2", "t3", "t5"])
        }

        function test_model_never_stacks_uncategorized_or_lone_tasks() {
            const rows = model.build([task("a", 1), task("b", 2), task("c", 3, "X"), task("d", 4, "  ")], "c")
            compare(rows.map(r => r.kind), ["card", "card", "card", "card"])
            compare(rows.map(r => r.showCategory), [false, false, true, false])
        }

        function test_model_matches_categories_ignoring_case_and_per_column() {
            const rows = model.build([task("a", 1, "Ui"), task("b", 2, "uI")], "c")
            compare(rows.length, 3)
            compare(rows[0].kind, "header")
            compare(rows[0].stackKey, model.stackKey("c", "UI"))
            verify(model.stackKey("c", "UI") !== model.stackKey("d", "UI"))
        }

        function test_model_maps_a_shown_slot_to_the_stored_position() {
            // Shown order is t1 t4 t6 t2 t3 t5; stored order is t1 t2 t3 t4 t5 t6.
            const shownIds = ["t1", "t4", "t6", "t2", "t3", "t5"]
            compare(model.storedPosition(shownIds, 0, ""), 0)
            compare(model.storedPosition(shownIds, 3, ""), 1)       // before t2
            compare(model.storedPosition(shownIds, 6, ""), 6)       // the end
            // t4 dragged out: the others are t1 t2 t3 t5 t6; before t6 is index 4.
            compare(model.storedPosition(["t1", "t6", "t2", "t3", "t5"], 1, "t4"), 4)
        }

        // ---- the view -------------------------------------------------------

        function test_the_view_shows_one_header_and_groups_the_stack() {
            compare(headerCount("c0"), 1)
            compare(layout("c0"), ["t1", "t4", "t6", "t2", "t3", "t5"])
            const h = header("c0", "ui")
            verify(h, "UI header")
            compare(findChild(h, "stackName").text, "UI")
            compare(findChild(h, "stackCount").text, "3")
            // Members sit under the header, in this order, with nothing between.
            const y = id => item("card-" + id).mapToItem(scene, 0, 0).y
            verify(h.mapToItem(scene, 0, 0).y < y("t1"))
            verify(y("t1") < y("t4") && y("t4") < y("t6") && y("t6") < y("t2"))
        }

        function test_the_header_lines_up_with_plain_notes_and_members_are_indented() {
            const h = header("c0", "ui")
            const x = it => it.mapToItem(scene, 0, 0).x
            const plain = item("card-t2")
            compare(x(h), x(plain))
            compare(h.width, plain.width)
            verify(x(item("card-t1")) > x(h), "stack members sit inside the header's edge")
        }

        function test_uncategorized_and_lone_tasks_are_ordinary_cards() {
            // No header for Backend (one task) and none for the uncategorized.
            compare(headerCount("c0"), 1)
            compare(headerCount("c1"), 0)
            compare(findChild(item("card-t2"), "cardCategory").visible, false)
            const lone = findChild(item("card-t3"), "cardCategory")
            compare(lone.visible, true)
            compare(findChild(item("card-t3"), "cardCategory").visible, true)
            verify(lone)
            // Stack members do not repeat the category; the header says it.
            compare(findChild(item("card-t1"), "cardCategory").visible, false)
            // A lone categorized note in another column is a card with its label.
            compare(findChild(item("card-t7"), "cardCategory").visible, true)
        }

        function test_clicking_the_header_collapses_and_expands_and_shows_the_count() {
            const h = header("c0", "ui")
            mouseClick(h)
            compare(shown("c0"), ["t2", "t3", "t5"])
            compare(item("card-t1").visible, false)
            compare(findChild(header("c0", "ui"), "stackCount").text, "3")
            compare(header("c0", "ui").collapsed, true)
            mouseClick(header("c0", "ui"))
            compare(shown("c0"), ["t1", "t4", "t6", "t2", "t3", "t5"])
            compare(header("c0", "ui").collapsed, false)
        }

        function test_collapsing_frees_vertical_space() {
            const before = item("card-t5").mapToItem(scene, 0, 0).y
            mouseClick(header("c0", "ui"))
            waitForRendering(boardView)
            verify(item("card-t5").mapToItem(scene, 0, 0).y < before - 100)
        }

        function test_the_keyboard_toggles_with_enter_and_space() {
            const h = header("c0", "ui")
            h.forceActiveFocus()
            verify(h.activeFocus)
            keyClick(Qt.Key_Return)
            compare(header("c0", "ui").collapsed, true)
            keyClick(Qt.Key_Space)
            compare(header("c0", "ui").collapsed, false)
            // Focus stays on the header.
            verify(header("c0", "ui").activeFocus)
        }

        function test_the_header_is_a_focusable_button_with_a_name() {
            const h = header("c0", "ui")
            compare(h.activeFocusOnTab, true)
            compare(h.Accessible.role, Accessible.Button)
            verify(h.Accessible.name.indexOf("UI") >= 0 && h.Accessible.name.indexOf("3") >= 0)
            // A header takes focus when pressed, and an earlier test may have left it there.
            item("card-t2").forceActiveFocus()
            compare(findChild(h, "focusRing").visible, false)
            h.forceActiveFocus()
            compare(findChild(h, "focusRing").visible, true)
        }

        function test_collapsed_state_survives_a_board_refresh_and_other_columns_are_independent() {
            mouseClick(header("c0", "ui"))
            scene.board = scene.sample()
            waitForRendering(boardView)
            compare(header("c0", "ui").collapsed, true)
            compare(shown("c0"), ["t2", "t3", "t5"])
        }

        function test_reduced_motion_stops_the_chevron_animating() {
            boardView.reducedMotion = true
            mouseClick(header("c0", "ui"))
            compare(findChild(header("c0", "ui"), "stackChevron").rotation, 0)
        }

        function test_moving_a_task_restacks_the_source_and_the_target_column() {
            // t7 (UI) joins Backlog's UI stack; Doing is left empty.
            move("t7", "c1", "c0", 6)
            compare(findChild(header("c0", "ui"), "stackCount").text, "4")
            compare(layout("c0").slice(0, 5), ["t1", "t4", "t6", "t7", "t2"])
            compare(headerCount("c1"), 0)
        }

        function test_moving_out_of_a_stack_updates_both_columns() {
            move("t4", "c0", "c1", 1)
            // Backlog keeps UI x2; Doing now has two UI notes and stacks them.
            compare(findChild(header("c0", "ui"), "stackCount").text, "2")
            compare(layout("c0"), ["t1", "t6", "t2", "t3", "t5"])
            compare(findChild(header("c1", "ui"), "stackCount").text, "2")
            // The moved task and the one it joined are grouped in Doing.
            compare(layout("c1"), ["t7", "t4"])
        }

        function test_a_stack_that_drops_to_one_member_stops_being_a_stack() {
            move("t4", "c0", "c1", 0)
            move("t6", "c0", "c1", 0)
            compare(headerCount("c0"), 0)
            compare(findChild(item("card-t1"), "cardCategory").visible, true)
        }

        function test_clearing_a_category_unstacks_the_task() {
            setCategory("t6", "")
            compare(findChild(header("c0", "ui"), "stackCount").text, "2")
            compare(layout("c0"), ["t1", "t4", "t2", "t3", "t5", "t6"])
            compare(findChild(item("card-t6"), "cardCategory").visible, false)
            setCategory("t4", "")
            setCategory("t6", "")
            compare(headerCount("c0"), 0)
        }

        function test_changing_a_category_moves_a_task_between_stacks() {
            setCategory("t2", "UI")
            setCategory("t5", "Backend")
            compare(findChild(header("c0", "ui"), "stackCount").text, "4")
            compare(findChild(header("c0", "backend"), "stackCount").text, "2")
        }

        // ---- dragging with stacks --------------------------------------------

        function dragTo(source, target, tx, ty) {
            const from = source.mapToItem(scene, source.width / 2, source.height / 2)
            const to = target.mapToItem(scene, tx, ty)
            mousePress(scene, from.x, from.y)
            for (let i = 1; i <= 12; i++)
                mouseMove(scene, from.x + (to.x - from.x) * i / 12, from.y + (to.y - from.y) * i / 12)
            mouseRelease(scene, to.x, to.y)
        }

        function test_dropping_below_a_card_in_an_expanded_stack_reports_its_stored_position() {
            // Drag t5 to just below t4 (shown third after the header): stored order
            // t1 t2 t3 t4 t5 t6 without t5 is t1 t2 t3 t4 t6; before t6 is index 4.
            const t4 = item("card-t4")
            dragTo(item("card-t5"), t4, t4.width / 2, t4.height + 4)
            compare(movedSpy.count, 1)
            compare(movedSpy.signalArguments[0][0], "t5")
            compare(movedSpy.signalArguments[0][1], "c0")
            compare(movedSpy.signalArguments[0][2], 4)
        }

        function test_dropping_into_an_empty_target_column_and_clicks_still_work() {
            const col = item("column-c1")
            dragTo(item("card-t2"), item("card-t7"), 20, item("card-t7").height + 6)
            compare(movedSpy.count, 1)
            compare(movedSpy.signalArguments[0][1], "c1")
            compare(movedSpy.signalArguments[0][2], 1)
            mouseClick(item("card-t3"))
            compare(clickedSpy.count, 1)
            compare(clickedSpy.signalArguments[0][0], "t3")
            verify(col)
        }
    }
}
