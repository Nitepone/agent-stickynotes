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

    // Stand-in for the dictionary's suggestions: "teh" has two, "wrold" none.
    property var suggester: function(word) {
        return word === "teh" ? ["the", "tech"] : []
    }

    FormTextArea {
        id: field
        objectName: "field"
        width: 400
        height: 120
        text: "Hello teh wrold"
        spellRanges: scene.checker
        spellSuggestions: scene.suggester
    }

    WrappingField {
        id: listItem
        y: 140
        width: 400
        text: "teh fox"
        spellRanges: scene.checker
        spellSuggestions: scene.suggester
    }

    TestCase {
        name: "SpellUnderline"
        when: windowShown

        function init() {
            field.spellRanges = scene.checker
            field.spellSuggestions = scene.suggester
            listItem.text = "teh fox"
            if (field.text !== "Hello teh wrold") {
                // Underlines follow a change after a short delay; let them catch up.
                field.text = "Hello teh wrold"
                wait(400)
            }
            wait(0)
        }

        function cleanup() {
            field.contextMenu.close()
            listItem.contextMenu.close()
            tryCompare(field.contextMenu, "visible", false)
            tryCompare(listItem.contextMenu, "visible", false)
        }

        // The menu's visible items with this objectName.
        function menuItems(menu, name) {
            const found = []
            for (let i = 0; i < menu.count; ++i) {
                const item = menu.itemAt(i)
                if (item && item.objectName === name && item.visible)
                    found.push(item)
            }
            return found
        }

        // Right-click inside the character at `pos` and wait for the menu.
        function rightClickAt(editor, pos) {
            const r = editor.positionToRectangle(pos)
            mouseClick(editor, r.x + 2, r.y + r.height / 2, Qt.RightButton)
            tryCompare(editor.contextMenu, "opened", true)
            // Let the menu lay out its items before anything is clicked.
            waitForRendering(editor.contextMenu.contentItem)
        }

        function test_right_click_on_a_misspelled_word_offers_its_suggestions() {
            rightClickAt(field, 7)   // inside "teh"
            const menu = field.contextMenu
            compare(menuItems(menu, "spellSuggestion").map(i => i.text), ["the", "tech"])
            compare(menuItems(menu, "noSuggestions").length, 0)
            for (const name of ["cutItem", "copyItem", "pasteItem", "selectAllItem"])
                compare(menuItems(menu, name).length, 1, name)
        }

        function test_choosing_a_suggestion_replaces_the_word_and_one_undo_restores_it() {
            tryCompare({ get n() { return underlines().length } }, "n", 2)
            rightClickAt(field, 7)
            mouseClick(menuItems(field.contextMenu, "spellSuggestion")[0])
            compare(field.text, "Hello the wrold")
            tryCompare(field.contextMenu, "visible", false)
            tryCompare({ get n() { return underlines().length } }, "n", 1, 2000)
            verify(field.activeFocus, "focus goes back to the field")

            keyClick(Qt.Key_Z, Qt.ControlModifier)
            compare(field.text, "Hello teh wrold", "one undo brings the word back")
            keyClick(Qt.Key_Z, Qt.ControlModifier | Qt.ShiftModifier)
            compare(field.text, "Hello the wrold", "and one redo replaces it again")
        }

        function test_a_word_without_suggestions_says_so() {
            rightClickAt(field, 12)  // inside "wrold"
            const menu = field.contextMenu
            compare(menuItems(menu, "spellSuggestion").length, 0)
            const none = menuItems(menu, "noSuggestions")
            compare(none.length, 1)
            verify(!none[0].enabled)
        }

        function test_a_correct_word_gets_only_the_edit_items() {
            rightClickAt(field, 2)   // inside "Hello"
            const menu = field.contextMenu
            compare(menuItems(menu, "spellSuggestion").length, 0)
            compare(menuItems(menu, "noSuggestions").length, 0)
            compare(menuItems(menu, "selectAllItem").length, 1)
        }

        function test_with_spell_check_off_there_are_no_spelling_items() {
            field.spellRanges = null
            rightClickAt(field, 7)
            const menu = field.contextMenu
            compare(menuItems(menu, "spellSuggestion").length, 0)
            compare(menuItems(menu, "noSuggestions").length, 0)
            compare(menuItems(menu, "pasteItem").length, 1)
        }

        function test_cut_from_the_menu_takes_the_selection() {
            field.forceActiveFocus()
            field.select(0, 6)       // "Hello "
            rightClickAt(field, 2)   // inside the selection: it stays
            const [cut] = menuItems(field.contextMenu, "cutItem")
            verify(cut.enabled)
            mouseClick(cut)
            compare(field.text, "teh wrold")
        }

        function test_shift_f10_opens_the_menu_for_the_word_at_the_cursor() {
            listItem.forceActiveFocus()
            listItem.cursorPosition = 1
            keyClick(Qt.Key_F10, Qt.ShiftModifier)
            tryCompare(listItem.contextMenu, "opened", true)
            waitForRendering(listItem.contextMenu.contentItem)
            compare(menuItems(listItem.contextMenu, "spellSuggestion").map(i => i.text), ["the", "tech"])
            listItem.contextMenu.close()
            tryCompare(listItem.contextMenu, "visible", false)

            // The list item's own key handling still runs: Enter adds no line.
            listItem.forceActiveFocus()
            keyClick(Qt.Key_Return)
            compare(listItem.text, "teh fox")
            keyClick(Qt.Key_Menu)
            tryCompare(listItem.contextMenu, "opened", true)
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
