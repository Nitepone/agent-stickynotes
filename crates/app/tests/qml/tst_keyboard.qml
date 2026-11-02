import QtQuick
import QtTest
import StickyNotes
import TestSupport

// Keyboard and screen-reader access to the board, with real key events.
Item {
    id: scene
    width: 1500
    height: 700

    readonly property var board: TestHelpers.sampleBoard({ doing: true })

    GlowTracker { id: tracker }

    FocusLabel {
        id: titleButton
        objectName: "boardTitle"
        text: "Test"
        accessibleName: "Board title: Test. Rename"
    }

    BoardView {
        id: boardView
        y: 40
        width: parent.width
        height: parent.height - 40
        board: scene.board
        dragLayer: dragLayer
        glowTracker: tracker
    }
    Item { id: dragLayer; anchors.fill: parent; z: 10 }

    SignalSpy { id: movedSpy; target: boardView; signalName: "taskMoved" }
    SignalSpy { id: clickedSpy; target: boardView; signalName: "taskClicked" }
    SignalSpy { id: addColumnSpy; target: boardView; signalName: "addColumnClicked" }
    SignalSpy { id: titleSpy; target: titleButton; signalName: "clicked" }

    TestCase {
        name: "Keyboard"
        when: windowShown

        function init() {
            tracker.ticker.running = false
            boardView.editMode = false
            boardView.reducedMotion = false
            for (const spy of [movedSpy, clickedSpy, addColumnSpy, titleSpy])
                spy.clear()
            titleButton.forceActiveFocus()
        }

        function item(name) {
            const found = findChild(boardView, name)
            verify(found, "no item named " + name)
            return found
        }

        function test_cards_expose_a_button_role_and_a_name_from_their_text() {
            for (const [id, text] of [["t0", "first"], ["t1", "second"], ["t2", "third"]]) {
                const card = item("card-" + id)
                compare(card.Accessible.role, Accessible.Button)
                compare(card.Accessible.name, text)
                verify(card.Accessible.focusable)
            }
            verify(item("card-t1").Accessible.description.indexOf("1 of 2") >= 0)
        }

        // Presses Tab until focus returns to where it started; records objectNames.
        function tabChain(limit) {
            const seen = []
            for (let i = 0; i < limit; i++) {
                keyClick(Qt.Key_Tab)
                const f = scene.Window.activeFocusItem
                if (!f || f === titleButton)
                    break
                seen.push(f.objectName)
            }
            return seen
        }

        function test_tab_reaches_every_card_and_control_in_a_sensible_order() {
            const seen = tabChain(30)
            // Per column: title, the collapse button, its cards, then the add-task button.
            compare(seen, ["title", "collapseColumn", "card-t0", "card-t1", "addTask",
                           "title", "collapseColumn", "card-t3", "addTask",
                           "title", "collapseColumn", "card-t2", "addTask"])
        }

        function test_tab_reaches_add_column_last_in_edit_mode() {
            boardView.editMode = true
            waitForRendering(boardView)
            titleButton.forceActiveFocus()
            const seen = tabChain(40)
            verify(seen.indexOf("addColumn") >= 0, "add column reachable: " + seen)
            compare(seen[seen.length - 1], "addColumn")
        }

        function test_the_board_title_is_a_focusable_button_with_keyboard_activation() {
            compare(titleButton.Accessible.role, Accessible.Button)
            verify(titleButton.activeFocusOnTab)
            verify(titleButton.activeFocus)
            keyClick(Qt.Key_Return)
            keyClick(Qt.Key_Space)
            compare(titleSpy.count, 2)
            verify(findChild(titleButton, "focusRing").visible, "focus ring is shown")
        }

        function test_enter_and_space_open_a_focused_card() {
            const card = item("card-t1")
            card.forceActiveFocus()
            keyClick(Qt.Key_Return)
            compare(clickedSpy.count, 1)
            compare(clickedSpy.signalArguments[0][0], "t1")
            keyClick(Qt.Key_Space)
            compare(clickedSpy.count, 2)
            keyClick(Qt.Key_Enter)
            compare(clickedSpy.count, 3)
        }

        function test_ctrl_right_and_left_move_a_card_one_column() {
            item("card-t0").forceActiveFocus()
            keyClick(Qt.Key_Right, Qt.ControlModifier)
            compare(movedSpy.count, 1)
            compare(movedSpy.signalArguments[0][0], "t0")
            compare(movedSpy.signalArguments[0][1], "c1")
            item("card-t2").forceActiveFocus()
            keyClick(Qt.Key_Left, Qt.ControlModifier)
            compare(movedSpy.count, 2)
            compare(movedSpy.signalArguments[1][0], "t2")
            compare(movedSpy.signalArguments[1][1], "c1")
        }

        function test_moving_past_the_first_or_last_column_does_nothing() {
            item("card-t0").forceActiveFocus()
            keyClick(Qt.Key_Left, Qt.ControlModifier)
            item("card-t2").forceActiveFocus()
            keyClick(Qt.Key_Right, Qt.ControlModifier)
            compare(movedSpy.count, 0)
        }

        function test_plain_arrows_do_not_move_and_edit_mode_disables_moving() {
            item("card-t0").forceActiveFocus()
            keyClick(Qt.Key_Right)
            compare(movedSpy.count, 0)
            boardView.editMode = true
            waitForRendering(boardView)
            item("card-t0").forceActiveFocus()
            keyClick(Qt.Key_Right, Qt.ControlModifier)
            compare(movedSpy.count, 0)
        }

        function test_add_column_is_a_focusable_button() {
            boardView.editMode = true
            waitForRendering(boardView)
            const add = item("addColumn")
            compare(add.Accessible.role, Accessible.Button)
            verify(add.Accessible.name.length > 0)
            add.forceActiveFocus()
            verify(add.activeFocus)
            keyClick(Qt.Key_Return)
            keyClick(Qt.Key_Space)
            compare(addColumnSpy.count, 2)
            compare(add.border.color.toString(), Theme.focusRing.toString())
        }

        function test_the_focus_ring_shows_only_on_the_focused_card() {
            const a = item("card-t0")
            const b = item("card-t1")
            a.forceActiveFocus()
            verify(findChild(a, "focusRing").visible)
            verify(!findChild(b, "focusRing").visible)
            compare(findChild(a, "focusRing").border.color.toString(), Theme.focusRing.toString())
        }

        function test_focus_survives_a_refresh_that_rebuilds_the_cards() {
            item("card-t1").forceActiveFocus()
            const state = boardView.scrollState()
            compare(state.focus, "t1")
            boardView.restoreScroll(state)
            compare(boardView.focusedTaskId(), "t1")
        }
    }
}
