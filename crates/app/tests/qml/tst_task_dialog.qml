import QtQuick
import QtQuick.Controls
import QtTest
import StickyNotes

Item {
    id: scene
    width: 1000
    height: 900

    readonly property string longText: "This requirement is intentionally long so that it cannot possibly fit on one line of the dialog and must wrap onto several lines instead of scrolling sideways."

    TaskDialog { id: dialog }

    TestCase {
        name: "TaskDialog"
        when: windowShown

        function taskJson(requirements, criteria) {
            return JSON.stringify({
                id: "t1", columnId: "c0", description: "d", extendedDescription: "",
                requirements: requirements,
                criteria: criteria,
                updatedAt: "2026-01-01T00:00:00Z",
            })
        }

        function open(requirements, criteria) {
            dialog.openTask(taskJson(requirements, criteria), "Backlog")
            waitForRendering(dialog.contentItem)
        }

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
    }
}
