import QtQuick
import QtTest
import StickyNotes

// Refreshing the board (as Main.qml does when an agent edits a task) must not
// reset the horizontal or per-column vertical scroll.
Item {
    id: scene
    width: 700
    height: 500

    property var board: makeBoard(30, 30, "")

    function makeBoard(n0, n1, editedText) {
        const tasks = (prefix, n) => {
            const list = []
            for (let i = 0; i < n; i++)
                list.push({ id: prefix + i, number: i + 1, cardText: (i === 3 && prefix === "a" ? editedText : "") + "task " + prefix + i + " with some text to fill the card", done: 0, total: 0 })
            return list
        }
        return {
            title: "Scroll",
            columns: [
                { id: "c0", title: "One", description: "", tasks: tasks("a", n0) },
                { id: "c1", title: "Two", description: "", tasks: tasks("b", n1) },
                { id: "c2", title: "Three", description: "", tasks: tasks("c", 2) },
                { id: "c3", title: "Four", description: "", tasks: tasks("d", 2) },
            ],
        }
    }

    // The same sequence Main.qml#refresh runs.
    function refresh(newBoard) {
        const view = boardView.scrollState()
        board = newBoard
        boardView.restoreScroll(view)
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
        name: "ScrollKeep"
        when: windowShown

        function flickOf(item) {
            return item
        }

        function column(id) {
            const c = findChild(boardView, "column-" + id)
            verify(c, "no column " + id)
            return c
        }

        function init() {
            tracker.ticker.running = false
            scene.board = scene.makeBoard(30, 30, "")
            wait(50)
        }

        function scrollAround() {
            const hflick = boardView.children[1] // the board Flickable
            verify(hflick.hasOwnProperty("contentX"))
            verify(hflick.contentWidth > hflick.width, "board is wider than the view")
            hflick.contentX = 150
            column("c0").scrollY = 400
            column("c1").scrollY = 250
            tryCompare(column("c0"), "scrollY", 400)
            return hflick
        }

        function test_an_edit_to_one_task_keeps_every_scroll_position() {
            const hflick = scrollAround()
            scene.refresh(scene.makeBoard(30, 30, "EDITED "))
            // The cards were rebuilt...
            compare(findChild(boardView, "card-a3").task.cardText.indexOf("EDITED"), 0)
            // ...and the offsets are the same, right away and once layout has settled.
            compare(hflick.contentX, 150)
            compare(column("c0").scrollY, 400)
            compare(column("c1").scrollY, 250)
            wait(300)
            compare(hflick.contentX, 150)
            compare(column("c0").scrollY, 400)
            compare(column("c1").scrollY, 250)
            compare(column("c2").scrollY, 0)
        }

        function test_scroll_is_kept_by_column_id_when_columns_move() {
            scrollAround()
            const b = scene.makeBoard(30, 30, "")
            b.columns = [b.columns[1], b.columns[0], b.columns[2], b.columns[3]]
            scene.refresh(b)
            wait(300)
            compare(column("c0").scrollY, 400)
            compare(column("c1").scrollY, 250)
        }

        function test_deleting_the_scrolled_to_tasks_clamps_instead_of_leaving_the_view_out_of_range() {
            scrollAround()
            scene.refresh(scene.makeBoard(3, 30, ""))
            wait(300)
            const c0 = column("c0")
            verify(c0.scrollY >= 0)
            verify(c0.scrollY <= Math.max(0, c0.maxScrollY()) + 0.5, "c0 within its content")
            compare(c0.scrollY, 0)
            compare(column("c1").scrollY, 250)
        }

        function test_deleting_the_scrolled_to_column_clamps_the_board() {
            const hflick = scrollAround()
            const b = scene.makeBoard(30, 30, "")
            b.columns = [b.columns[0]]
            scene.refresh(b)
            wait(300)
            verify(hflick.contentX <= Math.max(0, hflick.contentWidth - hflick.width) + 0.5)
            verify(hflick.contentX >= 0)
            compare(column("c0").scrollY, 400)
        }
    }
}
