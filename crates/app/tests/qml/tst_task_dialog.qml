import QtQuick
import QtQuick.Controls
import QtTest
import StickyNotes

Item {
    id: scene
    width: 1000
    height: 900

    readonly property string longText: "This requirement is intentionally long so that it cannot possibly fit on one line of the dialog and must wrap onto several lines instead of scrolling sideways."

    TaskDialog {
        id: dialog
        relationOptions: [
            { value: "blocks", label: "blocks" },
            { value: "blocked_by", label: "is blocked by" },
            { value: "relates_to", label: "relates to" },
        ]
        linkCandidates: [
            { id: "t1", columnTitle: "Backlog", text: "the task itself", label: "Backlog \u2014 the task itself" },
            { id: "t2", columnTitle: "Backlog", text: "Write the docs", label: "Backlog \u2014 Write the docs" },
            { id: "t3", columnTitle: "Done", text: "Ship it", label: "Done \u2014 Ship it" },
        ]
    }
    SignalSpy { id: openSpy; target: dialog; signalName: "openTaskRequested" }

    TestCase {
        name: "TaskDialog"
        when: windowShown

        function taskJson(requirements, criteria, references) {
            return JSON.stringify({
                id: "t1", columnId: "c0", description: "d", extendedDescription: "",
                requirements: requirements,
                criteria: criteria,
                references: references || [],
                updatedAt: "2026-01-01T00:00:00Z",
            })
        }

        function open(requirements, criteria, references) {
            dialog.openTask(taskJson(requirements, criteria, references), "Backlog")
            waitForRendering(dialog.contentItem)
        }

        function init() { openSpy.clear() }
        function cleanup() { dialog.close() }

        function fields(name) {
            const found = []
            ;(function walk(item) {
                for (const child of item.children) {
                    if (child.objectName === name) found.push(child)
                    walk(child)
                }
            })(dialog.contentItem)
            return found
        }

        function form() { return JSON.parse(dialog.formJson()) }

        function test_long_requirement_wraps_and_grows() {
            open(["short", scene.longText], [])
            const [brief, lengthy] = fields("requirementField")
            verify(brief && lengthy)
            verify(lengthy.lineCount > 1, "long text should wrap, got " + lengthy.lineCount + " line(s)")
            verify(lengthy.height > brief.height, "wrapped field should be taller")
            compare(lengthy.contentWidth <= lengthy.width, true)
        }

        function test_field_grows_as_text_is_typed() {
            open([""], [])
            const [field] = fields("requirementField")
            const before = field.height
            field.text = scene.longText
            waitForRendering(dialog.contentItem)
            verify(field.height > before)
            field.text = "short again"
            waitForRendering(dialog.contentItem)
            compare(field.height, before)
        }

        function test_criteria_wrap_too() {
            open([], [{ id: "k1", text: scene.longText, done: false }])
            const [field] = fields("criterionField")
            verify(field.lineCount > 1)
        }

        function test_controls_align_with_first_line() {
            open([scene.longText], [{ id: "k1", text: scene.longText, done: true }])
            const [reqField] = fields("requirementField")
            const [remove] = fields("removeRequirement")
            const [critField] = fields("criterionField")
            const [check] = fields("criterionCheck")
            const [removeCrit] = fields("removeCriterion")
            verify(reqField.height > remove.height, "field should be taller than its button")
            // Buttons sit at the top of their rows, not vertically centred.
            compare(remove.mapToItem(reqField.parent, 0, 0).y, 0)
            compare(check.mapToItem(critField.parent, 0, 0).y, 0)
            compare(removeCrit.mapToItem(critField.parent, 0, 0).y, 0)
        }

        function test_enter_does_not_insert_line_break() {
            open(["one"], [{ id: "k1", text: "crit", done: false }])
            for (const name of ["requirementField", "criterionField"]) {
                const [field] = fields(name)
                field.forceActiveFocus()
                field.cursorPosition = field.text.length
                keyClick(Qt.Key_Return)
                keyClick(Qt.Key_Enter)
                verify(field.text.indexOf("\n") < 0, name + " must not contain a line break")
            }
            compare(form().requirements, ["one"])
            compare(form().criteria[0].text, "crit")
        }

        function test_pasted_newlines_become_spaces() {
            open(["x"], [])
            const [field] = fields("requirementField")
            field.text = "first line\nsecond line\n\nthird"
            compare(field.text, "first line second line third")
            compare(form().requirements, ["first line second line third"])
        }

        function test_edits_reach_the_form_json() {
            open(["a"], [{ id: "k1", text: "c", done: false }])
            const [req] = fields("requirementField")
            const [crit] = fields("criterionField")
            req.text = "a edited"
            crit.text = "c edited"
            compare(form().requirements, ["a edited"])
            compare(form().criteria[0].text, "c edited")
            compare(form().criteria[0].id, "k1")
        }

        // ---- references ----

        readonly property var blockedByDocs: [{
            taskId: "t2", relation: "blocked_by", relationLabel: "is blocked by",
            description: "Write the docs", columnTitle: "Backlog" }]

        function test_references_are_listed_and_in_the_form() {
            open([], [], blockedByDocs)
            compare(fields("referenceRelation").length, 1)
            compare(fields("referenceRelation")[0].text, "is blocked by")
            compare(fields("referenceLink")[0].text, "Write the docs")
            compare(form().references, [{ task: "t2", relation: "blocked_by" }])
        }

        function test_clicking_a_reference_requests_that_task() {
            open([], [], blockedByDocs)
            mouseClick(fields("referenceLink")[0])
            compare(openSpy.count, 1)
            compare(openSpy.signalArguments[0][0], "t2")
        }

        function test_remove_reference() {
            open([], [], blockedByDocs)
            mouseClick(fields("removeReference")[0])
            compare(fields("referenceRelation").length, 0)
            compare(form().references, [])
        }

        function test_add_reference_with_dropdowns() {
            open([], [])
            const [relation] = fields("relationBox")
            const [target] = fields("targetBox")
            const [add] = fields("addReference")
            verify(!add.enabled, "Add needs a chosen task")
            relation.currentIndex = 0
            target.currentIndex = 1
            verify(add.enabled)
            mouseClick(add)
            compare(form().references, [{ task: "t3", relation: "blocks" }])
            compare(fields("referenceLink")[0].text, "Ship it")
            compare(target.currentIndex, -1)
        }

        function test_a_task_cannot_link_to_itself() {
            open([], [])
            const [target] = fields("targetBox")
            compare(target.count, 2)
            for (let i = 0; i < target.count; i++)
                verify(target.valueAt(i) !== "t1")
        }

        function test_adding_an_existing_target_changes_its_relation() {
            open([], [], blockedByDocs)
            dialog.addReference("t2", "relates_to")
            compare(form().references, [{ task: "t2", relation: "relates_to" }])
            compare(fields("referenceRelation").length, 1)
        }

        function test_new_tasks_cannot_be_linked_yet() {
            dialog.openNew({ id: "c0", title: "Backlog" })
            waitForRendering(dialog.contentItem)
            verify(!("references" in form()), "create form must not carry references")
            verify(!fields("addReference")[0].visible)
        }

        function test_isEdited_tracks_changes_to_references() {
            open([], [], blockedByDocs)
            verify(!dialog.isEdited())
            mouseClick(fields("removeReference")[0])
            verify(dialog.isEdited())
        }
    }
}
