import QtQuick
import QtTest
import StickyNotes

// View-level tests: real mouse drags against BoardView/TrashCan with a
// static board. No controller involved; we only check emitted intents.
Item {
    id: scene
    width: 1500
    height: 800

    readonly property var board: ({
        title: "Test",
        columns: [
            { id: "c0", title: "Backlog", description: "Unscoped", tasks: [
                { id: "t0", number: 1, cardText: "first", done: 0, total: 0 },
                { id: "t1", number: 2, cardText: "second", done: 1, total: 2 },
            ] },
            { id: "c1", title: "Doing", description: "", tasks: [] },
            { id: "c2", title: "Done", description: "", tasks: [
                { id: "t2", number: 12, cardText: "third", done: 2, total: 2 },
            ] },
        ],
    })

    GlowTracker { id: tracker }

    BoardView {
        id: boardView
        width: parent.width
        height: parent.height - 80
        board: scene.board
        dragLayer: dragLayer
        glowTracker: tracker
    }

    // Inside the default offscreen window, over empty board space.
    TrashCan {
        id: trash
        x: 1000
        y: 300
    }

    Item { id: dragLayer; anchors.fill: parent; z: 10 }

    SignalSpy { id: movedSpy; target: boardView; signalName: "taskMoved" }
    SignalSpy { id: columnMovedSpy; target: boardView; signalName: "columnMoved" }
    SignalSpy { id: clickedSpy; target: boardView; signalName: "taskClicked" }
    SignalSpy { id: titleSpy; target: boardView; signalName: "columnTitleClicked" }
    SignalSpy { id: addSpy; target: boardView; signalName: "addTaskClicked" }
    SignalSpy { id: trashSpy; target: trash; signalName: "taskDropped" }

    TestCase {
        name: "BoardView"
        when: windowShown

        function init() {
            tracker.ticker.running = false
            tracker.records = ({})
            tracker.lastInteraction = 0
            boardView.reducedMotion = false
            boardView.editMode = false
            for (const spy of [movedSpy, columnMovedSpy, clickedSpy, titleSpy, addSpy, trashSpy])
                spy.clear()
        }

        function item(name) {
            const found = findChild(boardView, name)
            verify(found, "no item named " + name)
            return found
        }

        // Drag `source` (grabbed at its centre) so the pointer ends on `target` at (tx, ty).
        function dragTo(source, target, tx, ty) {
            const from = source.mapToItem(scene, source.width / 2, source.height / 2)
            const to = target.mapToItem(scene, tx, ty)
            mousePress(scene, from.x, from.y)
            const steps = 12
            for (let i = 1; i <= steps; i++)
                mouseMove(scene, from.x + (to.x - from.x) * i / steps, from.y + (to.y - from.y) * i / steps)
            mouseRelease(scene, to.x, to.y)
        }

        function test_drag_task_to_empty_column() {
            const col = item("column-c1")
            dragTo(item("card-t0"), col, col.width / 2, 150)
            compare(movedSpy.count, 1)
            compare(movedSpy.signalArguments[0][0], "t0")
            compare(movedSpy.signalArguments[0][1], "c1")
            compare(movedSpy.signalArguments[0][2], 0)
        }

        function test_drag_task_below_sibling() {
            const second = item("card-t1")
            dragTo(item("card-t0"), second, second.width / 2, second.height + 4)
            compare(movedSpy.count, 1)
            compare(movedSpy.signalArguments[0][1], "c0")
            compare(movedSpy.signalArguments[0][2], 1)
        }

        function test_drag_task_above_existing() {
            const third = item("card-t2")
            dragTo(item("card-t1"), third, third.width / 2, 2)
            compare(movedSpy.count, 1)
            compare(movedSpy.signalArguments[0][0], "t1")
            compare(movedSpy.signalArguments[0][1], "c2")
            compare(movedSpy.signalArguments[0][2], 0)
        }

        function test_drag_task_to_trash() {
            dragTo(item("card-t2"), trash, trash.width / 2, trash.height / 2)
            compare(trashSpy.count, 1)
            compare(trashSpy.signalArguments[0][0], "t2")
            compare(movedSpy.count, 0)
        }

        function test_click_task_and_title() {
            mouseClick(item("card-t1"))
            compare(clickedSpy.count, 1)
            compare(clickedSpy.signalArguments[0][0], "t1")
            const title = findChild(item("column-c2"), "title")
            mouseClick(title, 5, title.height / 2)
            compare(titleSpy.count, 1)
            compare(titleSpy.signalArguments[0][0].id, "c2")
        }

        function test_add_task_button() {
            mouseClick(findChild(item("column-c1"), "addTask"))
            compare(addSpy.count, 1)
            compare(addSpy.signalArguments[0][0].id, "c1")
        }

        function test_edit_mode_reorders_columns() {
            boardView.editMode = true
            waitForRendering(boardView)
            const grip = findChild(item("column-c0"), "grip")
            const last = item("column-c2")
            dragTo(grip, last, last.width - 10, 40)
            compare(columnMovedSpy.count, 1)
            compare(columnMovedSpy.signalArguments[0][0], "c0")
            compare(columnMovedSpy.signalArguments[0][1], 2)
        }

        function test_edit_mode_disables_task_drag() {
            boardView.editMode = true
            waitForRendering(boardView)
            const col = item("column-c1")
            dragTo(item("card-t0"), col, col.width / 2, 150)
            compare(movedSpy.count, 0)
        }

        function numberLabel(cardName) {
            return findChild(item(cardName), "cardNumber")
        }

        function test_cards_show_their_number_at_the_bottom_left() {
            const numbers = { "card-t0": "#1", "card-t1": "#2", "card-t2": "#12" }
            for (const name in numbers) {
                const card = item(name)
                const label = numberLabel(name)
                compare(label.text, numbers[name])
                // Bottom left: left edge of the note content, in the lower half.
                const p = label.mapToItem(card, 0, 0)
                verify(p.x < card.width / 4, name + " number should be on the left")
                verify(p.y > card.height / 2, name + " number should be in the lower half")
            }
        }

        function test_number_is_gray_and_does_not_collide_with_the_text_or_progress() {
            for (const name of ["card-t0", "card-t1"]) {
                const card = item(name)
                const label = numberLabel(name)
                compare(label.color.toString(), Theme.noteNumber.toString())
                verify(label.contentWidth <= label.width, "number is not truncated")
                const nb = label.mapToItem(card, 0, 0)
                // Nothing else in the footer row overlaps the number horizontally.
                for (const child of label.parent.children) {
                    if (child === label || !child.visible) continue
                    const cb = child.mapToItem(card, 0, 0)
                    verify(cb.x >= nb.x + label.width - 1, "footer item overlaps the number")
                }
            }
        }

        function test_clicking_the_number_still_opens_the_task() {
            mouseClick(numberLabel("card-t1"))
            compare(clickedSpy.count, 1)
            compare(clickedSpy.signalArguments[0][0], "t1")
        }

        // ---- glow on notes an agent changed ----

        function glowEdgeOf(cardName) {
            return findChild(item(cardName), "glowEdge")
        }

        function agentChanged(id, kind) {
            return { columns: [{ tasks: [{ id: id, agentChange: { at: 5000, kind: kind } }] }] }
        }

        function test_only_notes_the_tracker_flags_glow() {
            tracker.sync(agentChanged("t1", "moved"), 6000)
            verify(glowEdgeOf("card-t1").visible, "flagged note glows")
            verify(!glowEdgeOf("card-t0").visible, "others do not")
            verify(!glowEdgeOf("card-t2").visible)
        }

        function test_the_glow_follows_the_tracker_and_fades() {
            tracker.sync(agentChanged("t1", "edited"), 6000)
            compare(glowEdgeOf("card-t1").intensity, 1)
            verify(glowEdgeOf("card-t1").edited, "edited notes get the sheen")
            tracker.interact(7000)
            tracker.tick(17000)
            verify(Math.abs(glowEdgeOf("card-t1").intensity - 0.5) < 0.001)
            tracker.tick(27000)
            verify(!glowEdgeOf("card-t1").visible)
        }

        function test_reduced_motion_reaches_the_cards() {
            tracker.sync(agentChanged("t1", "edited"), 6000)
            const edge = glowEdgeOf("card-t1")
            verify(findChild(edge, "comet").visible)
            boardView.reducedMotion = true
            verify(!findChild(edge, "comet").visible)
            verify(edge.visible, "the static glow stays")
        }

        function test_a_glowing_note_still_drags_and_clicks_normally() {
            tracker.sync(agentChanged("t0", "edited"), 6000)
            mouseClick(item("card-t0"))
            compare(clickedSpy.count, 1)
            const col = item("column-c1")
            dragTo(item("card-t0"), col, col.width / 2, 150)
            compare(movedSpy.count, 1)
            compare(movedSpy.signalArguments[0][0], "t0")
        }
    }
}
