import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

Item {
    id: scene
    width: 500
    height: 300

    // Stand-in for the dictionary: "teh" and "wrold" are the misspelled words.
    property var checker: function(text) {
        const found = []
        const re = /\b(teh|wrold)\b/g
        let m
        while ((m = re.exec(text)) !== null)
            found.push([m.index, m[0].length])
        return found
    }

    FormTextArea {
        id: field
        objectName: "field"
        width: 400
        height: 120
        text: "Hello teh wrold"
        spellRanges: scene.checker
    }

    TestCase {
        name: "SpellUnderline"
        when: windowShown

        function init() {
            field.spellRanges = scene.checker
            field.text = "Hello teh wrold"
            wait(0)
        }

        function underlines() {
            const found = TestHelpers.findWhere(field, c => c.objectName === "spellUnderline" && c.visible)
            return found.sort((a, b) => a.x - b.x)
        }

        function test_misspelled_words_are_underlined_where_they_are() {
            tryCompare({ get n() { return underlines().length } }, "n", 2)
            const [first, second] = underlines()
            const teh = field.positionToRectangle(6)
            const tehEnd = field.positionToRectangle(9)
            fuzzyCompare(first.x, teh.x, 1)
            fuzzyCompare(first.width, tehEnd.x - teh.x, 1)
            // The line sits at the bottom of the text, not above it.
            verify(first.y > teh.y + teh.height / 2)
            verify(second.x > first.x + first.width, "second word is further right")
        }

        function test_underlines_use_the_theme_danger_color() {
            tryCompare({ get n() { return underlines().length } }, "n", 2)
            compare(underlines()[0].color.toString(), Theme.danger.toString())
        }

        function test_turning_it_off_removes_the_underlines_and_on_restores_them() {
            tryCompare({ get n() { return underlines().length } }, "n", 2)
            field.spellRanges = null
            tryCompare({ get n() { return underlines().length } }, "n", 0)
            field.spellRanges = scene.checker
            tryCompare({ get n() { return underlines().length } }, "n", 2)
        }

        function test_underlines_follow_what_is_typed() {
            tryCompare({ get n() { return underlines().length } }, "n", 2)
            field.text = "Hello world"
            tryCompare({ get n() { return underlines().length } }, "n", 0, 2000)
            field.text = "teh teh teh"
            tryCompare({ get n() { return underlines().length } }, "n", 3, 2000)
        }

        function test_a_word_that_wraps_is_still_underlined_on_its_first_line() {
            field.text = "word word word word word word word word word word word word word word word wrold"
            tryCompare({ get n() { return underlines().length } }, "n", 1, 2000)
            const u = underlines()[0]
            verify(u.y > 20, "on a later line: " + u.y)
            verify(u.x + u.width <= field.width, "stays inside the field")
        }

        function test_no_checker_means_no_underlines() {
            field.spellRanges = null
            field.text = "teh teh"
            wait(400)
            compare(underlines().length, 0)
        }

        function test_underlines_never_take_clicks_from_the_text() {
            tryCompare({ get n() { return underlines().length } }, "n", 2)
            const u = underlines()[0]
            mouseClick(u, 2, 1)
            verify(field.activeFocus, "the click reached the text area")
        }
    }
}
