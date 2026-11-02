import QtQuick
import QtTest
import StickyNotes
import TestSupport

// Variable note colors: the category-to-color assignment in Theme, the palettes'
// readability, and what a board shows with the style on and off.
Item {
    id: scene
    width: 1500
    height: 800

    // Tasks in one column: two categories (one spelled two ways), a blank one and a bare one.
    readonly property var board: ({
        title: "Test",
        categories: ["Backend", "ui"],
        columns: [
            { id: "c0", title: "Backlog", description: "", tasks: [
                { id: "t0", number: 1, cardText: "api", category: "Backend", done: 0, total: 0 },
                { id: "t1", number: 2, cardText: "button", category: "ui", done: 0, total: 0 },
                { id: "t2", number: 3, cardText: "layout", category: "UI", done: 0, total: 0 },
                { id: "t3", number: 4, cardText: "loose", done: 0, total: 0 },
                { id: "t4", number: 5, cardText: "blank", category: "  ", done: 0, total: 0 },
            ] },
            { id: "c1", title: "Doing", description: "", tasks: [] },
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
    Item { id: dragLayer; anchors.fill: parent; z: 10 }

    TestCase {
        name: "NoteColors"
        when: windowShown

        function init() {
            tracker.ticker.running = false
            tracker.records = ({})
            reset()
        }

        function cleanup() { reset() }

        function reset() {
            Theme.mode = "light"
            Theme.noteColor = ""
            Theme.noteStyle = "user"
            Theme.notePalette = ""
            Theme.noteCategories = []
        }

        function same(a, b, message) {
            compare(Qt.color(a).toString(), Qt.color(b).toString(), message)
        }

        function palette(id) { return Theme.paletteById(id).colors }

        function assign(categories, id) {
            return Theme.assignCategoryColors(categories, palette(id || "pastel"))
        }

        function paper(taskId) {
            const card = TestHelpers.findByName(boardView, "card-" + taskId)
            verify(card, "card " + taskId)
            return TestHelpers.findByName(card, "notePaper")
        }

        function hueGap(a, b) {
            const d = Math.abs(Qt.color(a).hslHue - Qt.color(b).hslHue) * 360
            return Math.min(d, 360 - d)
        }

        // ---- the palettes ------------------------------------------------

        function test_there_are_several_palettes_with_enough_distinct_valid_colors() {
            verify(Theme.notePalettes.length >= 3)
            const ids = {}
            for (const p of Theme.notePalettes) {
                verify(!ids[p.id], "duplicate palette id " + p.id)
                ids[p.id] = true
                verify(p.name.length > 0)
                verify(p.colors.length >= 10, p.id + " has " + p.colors.length + " colors")
                const seen = {}
                for (const c of p.colors) {
                    verify(Theme.isHexColor(c), c)
                    verify(!seen[c], "duplicate color " + c + " in " + p.id)
                    seen[c] = true
                }
            }
        }

        function test_the_first_colors_of_every_palette_are_far_apart_in_hue() {
            for (const p of Theme.notePalettes) {
                for (let i = 0; i < 4; i++)
                    for (let j = i + 1; j < 4; j++)
                        verify(hueGap(p.colors[i], p.colors[j]) >= 30,
                               p.id + " colors " + i + " and " + j + ": " + hueGap(p.colors[i], p.colors[j]))
            }
        }

        function test_the_palette_ids_resolve_and_unknown_ones_use_the_first() {
            for (const p of Theme.notePalettes)
                compare(Theme.paletteById(p.id).id, p.id)
            compare(Theme.paletteById("nope").id, Theme.notePalettes[0].id)
            compare(Theme.paletteById("").id, Theme.notePalettes[0].id)
        }

        function test_text_is_readable_on_every_palette_color_in_both_modes() {
            const failures = []
            const tokens = [Theme.noteTextOn, Theme.noteNumberOn, Theme.noteSubtleTextOn, Theme.noteDoneTextOn]
            for (const mode of ["light", "dark"]) {
                Theme.mode = mode
                for (const p of Theme.notePalettes) {
                    for (const c of p.colors) {
                        tokens.forEach((fn, i) => {
                            const ratio = Theme.contrast(fn(c), c)
                            if (ratio < 4.5)
                                failures.push(mode + " " + p.id + " " + c + " token " + i + " = " + ratio.toFixed(2))
                        })
                        // The chip behind the category label is darker than the note.
                        const chip = Theme.contrast(Theme.noteChipTextOn(c), Theme.noteChipOn(c))
                        if (chip < 4.5)
                            failures.push(mode + " " + p.id + " " + c + " chip = " + chip.toFixed(2))
                    }
                }
            }
            compare(failures, [], "pairs below 4.5:1")
        }

        function test_the_usual_dark_note_text_already_works_on_every_palette_color() {
            // No lightening or darkening of the text is needed on a palette color.
            for (const p of Theme.notePalettes)
                for (const c of p.colors) {
                    verify(Theme.contrast("#2b2813", c) >= 4.5, c)
                    same(Theme.noteTextOn(c), "#2b2813", c)
                }
        }

        // ---- assignment --------------------------------------------------

        function test_the_order_categories_were_created_in_changes_nothing() {
            const a = assign(["Backend", "docs", "ui", "api"])
            const b = assign(["ui", "api", "Backend", "docs"])
            compare(JSON.stringify(a), JSON.stringify(b))
            compare(Object.keys(a).length, 4)
        }

        function test_case_and_spaces_do_not_make_a_different_category() {
            const a = assign(["Backend", "UI"])
            const b = assign(["backend", " ui "])
            compare(JSON.stringify(a), JSON.stringify(b))
            compare(Object.keys(assign(["ui", "UI", "Ui "])).length, 1)
        }

        function test_categories_get_distinct_colors_while_the_palette_has_some_left() {
            const colors = palette("pastel")
            const names = []
            for (let i = 0; i < colors.length; i++)
                names.push("cat" + String.fromCharCode(97 + i))
            const seen = {}
            for (const n in assign(names))
                seen[assign(names)[n]] = true
            compare(Object.keys(seen).length, colors.length)
            // And only palette colors are used.
            for (const n in assign(names))
                verify(colors.indexOf(assign(names)[n]) >= 0)
        }

        function test_the_first_categories_take_the_first_palette_colors_alphabetically() {
            const a = assign(["b", "a", "c"])
            compare(a["a"], palette("pastel")[0])
            compare(a["b"], palette("pastel")[1])
            compare(a["c"], palette("pastel")[2])
        }

        function test_more_categories_than_colors_wrap_and_every_one_still_has_a_palette_color() {
            const colors = palette("candy")
            const names = []
            for (let i = 0; i < colors.length * 2 + 3; i++)
                names.push("c" + String(100 + i))
            const a = Theme.assignCategoryColors(names, colors)
            compare(Object.keys(a).length, names.length)
            for (const n of names)
                verify(colors.indexOf(a[n]) >= 0, n)
            compare(a["c100"], colors[0])
            compare(a["c" + (100 + colors.length)], colors[0])
        }

        function test_the_assignment_is_recalculated_when_the_set_changes() {
            Theme.noteCategories = ["b", "c"]
            const before = Theme.categoryColors["c"]
            compare(before, palette("pastel")[1])
            Theme.noteCategories = ["a", "b", "c"]          // added
            compare(Theme.categoryColors["c"], palette("pastel")[2])
            Theme.noteCategories = ["a", "c"]               // removed
            compare(Theme.categoryColors["c"], palette("pastel")[1])
            Theme.noteCategories = ["a", "c2"]              // renamed
            verify(Theme.categoryColors["c"] === undefined)
            compare(Theme.categoryColors["c2"], palette("pastel")[1])
        }

        function test_no_categories_means_no_assignments() {
            compare(Object.keys(assign([])).length, 0)
            compare(Object.keys(Theme.assignCategoryColors(null, palette("pastel"))).length, 0)
            compare(Object.keys(assign(["", "  "])).length, 0)
        }

        function test_the_same_categories_give_the_same_colors_on_every_load() {
            Theme.noteCategories = ["Backend", "ui"]
            const first = JSON.stringify(Theme.categoryColors)
            Theme.noteCategories = []
            Theme.noteCategories = ["ui", "Backend"]
            compare(JSON.stringify(Theme.categoryColors), first)
        }

        function test_the_chosen_palette_is_the_one_used() {
            Theme.noteCategories = ["a"]
            Theme.notePalette = "candy"
            compare(Theme.categoryColors["a"], palette("candy")[0])
            Theme.notePalette = "cool"
            compare(Theme.categoryColors["a"], palette("cool")[0])
        }

        // ---- the color of a note ----------------------------------------

        function test_with_the_style_off_every_note_keeps_its_color() {
            Theme.noteCategories = ["Backend", "ui"]
            for (const category of ["Backend", "ui", "", undefined])
                same(Theme.noteColorFor(category), Theme.defaultNote)
            Theme.noteColor = "#bfe3ff"
            same(Theme.noteColorFor("ui"), "#bfe3ff")
        }

        function test_with_the_style_on_notes_use_their_categorys_palette_color() {
            Theme.noteStyle = "variable"
            Theme.noteCategories = ["Backend", "ui"]
            same(Theme.noteColorFor("Backend"), palette("pastel")[0])
            same(Theme.noteColorFor("ui"), palette("pastel")[1])
            same(Theme.noteColorFor("UI"), palette("pastel")[1])
        }

        function test_uncategorized_notes_keep_the_users_note_color_in_variable_style() {
            Theme.noteStyle = "variable"
            Theme.noteCategories = ["Backend"]
            same(Theme.noteColorFor(""), Theme.defaultNote)
            same(Theme.noteColorFor(undefined), Theme.defaultNote)
            Theme.noteColor = "#bfe3ff"
            same(Theme.noteColorFor("  "), "#bfe3ff")
        }

        // ---- cards on the board -----------------------------------------

        function test_cards_keep_the_note_color_when_the_style_is_off() {
            for (const id of ["t0", "t1", "t2", "t3", "t4"])
                same(paper(id).color, Theme.defaultNote, id)
            Theme.noteCategories = ["Backend", "ui"]
            for (const id of ["t0", "t1", "t2", "t3", "t4"])
                same(paper(id).color, Theme.defaultNote, id)
        }

        function test_cards_use_only_palette_colors_when_the_style_is_on() {
            Theme.noteCategories = scene.board.categories
            Theme.noteStyle = "variable"
            const colors = palette("pastel")
            same(paper("t0").color, colors[0])
            same(paper("t1").color, colors[1])
            same(paper("t2").color, colors[1], "UI is the same category as ui")
            same(paper("t3").color, Theme.defaultNote, "uncategorized")
            same(paper("t4").color, Theme.defaultNote, "blank category")
            verify(!Theme.sameColor(paper("t0").color, paper("t1").color))
        }

        function test_cards_follow_a_palette_change_and_stay_readable() {
            Theme.noteCategories = scene.board.categories
            Theme.noteStyle = "variable"
            Theme.notePalette = "candy"
            same(paper("t0").color, palette("candy")[0])
            same(paper("t1").color, palette("candy")[1])
            const card = TestHelpers.findByName(boardView, "card-t0")
            const number = TestHelpers.findByName(card, "cardNumber")
            verify(Theme.contrast(number.color, paper("t0").color) >= 4.5)
        }

        function test_cards_recolor_when_a_category_is_added() {
            Theme.noteStyle = "variable"
            Theme.noteCategories = ["Backend", "ui"]
            same(paper("t1").color, palette("pastel")[1])
            Theme.noteCategories = ["Admin", "Backend", "ui"]
            same(paper("t1").color, palette("pastel")[2])
            same(paper("t0").color, palette("pastel")[1])
        }

        function test_switching_the_style_off_again_restores_the_colors() {
            Theme.noteCategories = scene.board.categories
            Theme.noteStyle = "variable"
            Theme.noteStyle = "user"
            same(paper("t0").color, Theme.defaultNote)
        }
    }
}
