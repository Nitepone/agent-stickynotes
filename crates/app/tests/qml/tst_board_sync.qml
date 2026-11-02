import QtQuick
import QtTest
import StickyNotes

// The board is updated in place by id: a refresh with one changed task keeps
// every other column and card instance (hover, focus, glow, scroll), and adds,
// removals and moves produce the right board.
Item {
    id: scene
    width: 900
    height: 600

    property var board: makeBoard(5, 5, "")

    function tasks(prefix, n, editedIndex, editedText) {
        const list = []
        for (let i = 0; i < n; i++)
            list.push({ id: prefix + i, number: i + 1, cardText: (i === editedIndex ? editedText : "") + "task " + prefix + i,
                        done: 0, total: 0 })
        return list
    }

    // `editedText` prefixes the text of task a1.
    function makeBoard(n0, n1, editedText) {
        return {
            title: "Sync",
            columns: [
                { id: "c0", title: "One", description: "", tasks: tasks("a", n0, 1, editedText) },
                { id: "c1", title: "Two", description: "", tasks: tasks("b", n1, -1, "") },
            ],
        }
    }

    GlowTracker { id: tracker }
    BoardView {
        id: boardView
        anchors.fill: parent
        board: scene.board
        dragLayer: dragLayer
        glowTracker: tracker
    }
    Item { id: dragLayer; anchors.fill: parent; z: 10 }

    TestCase {
        name: "BoardSync"
        when: windowShown

        function init() {
            tracker.ticker.running = false
            scene.board = scene.makeBoard(5, 5, "")
            wait(50)
        }

        function card(id) {
            return findChild(boardView, "card-" + id)
        }

        // Every card on the board by task id, as the item instance.
        function cardInstances(board) {
            const found = {}
            for (const col of board.columns) {
                for (const t of col.tasks) {
                    const c = card(t.id)
                    verify(c, "no card " + t.id)
                    found[t.id] = c
                }
            }
            return found
        }

        function recreated(before, after) {
            let n = 0
            for (const id in before) {
                if (after[id] !== before[id])
                    n++
            }
            return n
        }

        function ids(columnId) {
            const col = findChild(boardView, "column-" + columnId)
            return col.cardItems("", false).map(c => c.task.id)
        }

        function columnIds() {
            return boardView.columnItems("").map(c => c.column.id)
        }

        function test_editing_one_task_recreates_no_other_card() {
            const before = cardInstances(scene.board)
            const columns = boardView.columnItems("")
            scene.board = scene.makeBoard(5, 5, "EDITED ")
            const after = cardInstances(scene.board)
            compare(recreated(before, after), 0)
            compare(card("a1").task.cardText, "EDITED task a1")
            compare(boardView.columnItems(""), columns)
        }

        function test_a_board_of_200_tasks_creates_few_items_for_one_edit() {
            scene.board = scene.makeBoard(100, 100, "")
            wait(100)
            const before = cardInstances(scene.board)
            scene.board = scene.makeBoard(100, 100, "EDITED ")
            const after = cardInstances(scene.board)
            verify(recreated(before, after) <= 5, "recreated " + recreated(before, after))
            compare(card("a1").task.cardText, "EDITED task a1")
        }

        function test_keyboard_focus_survives_an_edit_to_another_task() {
            const focused = card("b2")
            focused.forceActiveFocus()
            verify(focused.activeFocus)
            scene.board = scene.makeBoard(5, 5, "EDITED ")
            compare(card("b2"), focused)
            verify(focused.activeFocus)
        }

        function test_the_glow_of_an_unchanged_card_is_not_restarted() {
            tracker.sync(scene.board)
            const before = card("b3")
            const tickerRunning = tracker.ticker.running
            const glowBefore = before.glow
            scene.board = scene.makeBoard(5, 5, "EDITED ")
            tracker.sync(scene.board)
            compare(card("b3"), before)
            compare(before.glow, glowBefore)
            compare(tracker.ticker.running, tickerRunning)
        }

        function test_scroll_positions_are_unchanged_with_no_save_and_restore() {
            scene.board = scene.makeBoard(40, 40, "")
            wait(100)
            const hflick = boardView.children[1]
            hflick.contentX = 0
            const col = findChild(boardView, "column-c0")
            col.scrollY = 300
            tryCompare(col, "scrollY", 300)
            scene.board = scene.makeBoard(40, 40, "EDITED ")
            compare(col.scrollY, 300)
            wait(300)
            compare(col.scrollY, 300)
            compare(findChild(boardView, "column-c0"), col)
        }

        function test_adding_and_removing_tasks() {
            const b = scene.makeBoard(5, 5, "")
            b.columns[0].tasks.splice(2, 0, { id: "new", number: 99, cardText: "new", done: 0, total: 0 })
            b.columns[1].tasks.splice(0, 1)
            const keep = card("a0")
            scene.board = b
            compare(ids("c0"), ["a0", "a1", "new", "a2", "a3", "a4"])
            compare(ids("c1"), ["b1", "b2", "b3", "b4"])
            compare(card("a0"), keep)
            verify(!card("b0"))
        }

        function test_moving_a_task_between_columns_and_reordering_tasks() {
            const b = scene.makeBoard(5, 5, "")
            const moved = b.columns[0].tasks.splice(1, 1)[0]
            b.columns[1].tasks.splice(1, 0, moved)
            const t = b.columns[1].tasks
            b.columns[1].tasks = [t[4], t[0], t[1], t[2], t[3], t[5]].filter(x => x)
            scene.board = b
            compare(ids("c0"), ["a0", "a2", "a3", "a4"])
            compare(ids("c1"), ["b3", "b0", "a1", "b1", "b2", "b4"])
            const col = findChild(boardView, "column-c1")
            // Cards are laid out in model order.
            wait(50)
            const ys = col.cardItems("", false).map(c => col.cardTop(c))
            for (let i = 1; i < ys.length; i++)
                verify(ys[i] > ys[i - 1], "cards are stacked top to bottom in order")
        }

        function test_reordering_and_removing_columns() {
            const b = scene.makeBoard(5, 5, "")
            const first = findChild(boardView, "column-c0")
            b.columns = [b.columns[1], b.columns[0]]
            scene.board = b
            compare(columnIds(), ["c1", "c0"])
            compare(findChild(boardView, "column-c0"), first)
            wait(50)
            const xs = boardView.columnItems("").map(c => c.x)
            verify(xs[0] < xs[1], "columns are laid out in the new order")

            const c = scene.makeBoard(5, 5, "")
            c.columns = [c.columns[0]]
            scene.board = c
            compare(columnIds(), ["c0"])
        }

        function test_a_stack_header_updates_in_place() {
            const b = scene.makeBoard(5, 5, "")
            b.columns[0].tasks[0].category = "UI"
            b.columns[0].tasks[2].category = "UI"
            scene.board = b
            const col = findChild(boardView, "column-c0")
            const header = col.headerItems()[0]
            verify(header, "a stack header exists")
            compare(header.count, 2)
            const other = card("a3")
            const c = scene.makeBoard(5, 5, "")
            c.columns[0].tasks[0].category = "UI"
            c.columns[0].tasks[2].category = "UI"
            c.columns[0].tasks[3].category = "ui"
            scene.board = c
            compare(col.headerItems()[0], header)
            compare(header.count, 3)
            compare(card("a3"), other)
        }
    }
}
