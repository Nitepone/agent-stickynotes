import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

Item {
    id: scene
    width: 1000
    height: 760

    // Two extra sections prove the sidebar is built from whatever sections exist.
    PreferencesPage {
        id: page
        anchors.fill: parent

        PersonalizationSection {
            id: personalization
            themeMode: "light"
        }
        PreferencesSection { id: second; title: "Second"; objectName: "secondPage" }
        PreferencesSection { id: third; title: "Third"; objectName: "thirdPage" }
    }

    SignalSpy { id: backSpy; target: page; signalName: "backRequested" }
    SignalSpy { id: modeSpy; target: personalization; signalName: "themeModeChosen" }
    SignalSpy { id: primarySpy; target: personalization; signalName: "primaryColorChosen" }
    SignalSpy { id: secondarySpy; target: personalization; signalName: "secondaryColorChosen" }
    SignalSpy { id: resetSpy; target: personalization; signalName: "resetColorsRequested" }
    SignalSpy { id: noteSpy; target: personalization; signalName: "noteColorChosen" }
    SignalSpy { id: noteResetSpy; target: personalization; signalName: "resetNoteColorRequested" }
    SignalSpy { id: styleSpy; target: personalization; signalName: "noteStyleChosen" }
    SignalSpy { id: paletteSpy; target: personalization; signalName: "notePaletteChosen" }
    SignalSpy { id: motionSpy; target: personalization; signalName: "motionSettingChosen" }

    TestCase {
        name: "Preferences"
        when: windowShown

        function init() {
            for (const spy of [backSpy, modeSpy, primarySpy, secondarySpy, resetSpy, motionSpy, noteSpy, noteResetSpy,
                               styleSpy, paletteSpy])
                spy.clear()
            page.currentIndex = 0
            personalization.themeMode = "light"
            personalization.primaryColor = ""
            personalization.secondaryColor = ""
            personalization.motionSetting = "system"
            personalization.noteColor = ""
            personalization.noteStyle = "user"
            personalization.notePalette = ""
            Theme.noteColor = ""
            find("motionBox").currentIndex = 0
            Theme.mode = "light"
            Theme.primaryColor = ""
            Theme.secondaryColor = ""
            page.focusSidebar()
            waitForRendering(page)   // the theme change above re-polishes the page
        }

        function find(name, root) {
            return TestHelpers.findByName(root || page, name)
        }

        function entry(i) { return find("sidebarItem" + i) }

        // ---- sidebar -----------------------------------------------------

        function test_sidebar_lists_every_section_by_title() {
            compare(page.sectionCount, 3)
            compare(entry(0).text, "Personalization")
            compare(entry(1).text, "Second")
            compare(entry(2).text, "Third")
        }

        function test_personalization_is_shown_and_highlighted_by_default() {
            compare(page.currentIndex, 0)
            verify(entry(0).highlighted, "Personalization entry is active")
            verify(!entry(1).highlighted)
            verify(personalization.visible)
            verify(!second.visible)
            same(entry(0).background.color, Theme.primary, "active entry uses the primary color")
        }

        function same(a, b, message) {
            compare(Qt.color(a).toString(), Qt.color(b).toString(), message)
        }

        function test_clicking_an_entry_switches_the_page() {
            mouseClick(entry(1))
            compare(page.currentIndex, 1)
            verify(entry(1).highlighted && !entry(0).highlighted)
            verify(second.visible && !personalization.visible)
            mouseClick(entry(0))
            verify(personalization.visible)
        }

        function test_sidebar_works_from_the_keyboard() {
            verify(find("sidebar").activeFocus, "sidebar has focus")
            keyClick(Qt.Key_Down)
            compare(page.currentIndex, 1)
            verify(second.visible)
            keyClick(Qt.Key_Down)
            compare(page.currentIndex, 2)
            keyClick(Qt.Key_Down)
            compare(page.currentIndex, 2, "stops at the last section")
            keyClick(Qt.Key_Up)
            keyClick(Qt.Key_Up)
            compare(page.currentIndex, 0)
            keyClick(Qt.Key_Up)
            compare(page.currentIndex, 0, "stops at the first section")
        }

        function test_back_button_and_escape_return_to_the_board() {
            mouseClick(find("backButton"))
            compare(backSpy.count, 1)
            page.focusSidebar()
            keyClick(Qt.Key_Escape)
            compare(backSpy.count, 2)
        }

        function test_the_page_blocks_clicks_to_what_is_underneath() {
            // A MouseArea behind the content accepts every button.
            let blocker = null
            for (const child of page.children)
                for (const grandchild of child.children)
                    if (grandchild.hasOwnProperty("acceptedButtons") && grandchild.acceptedButtons === Qt.AllButtons)
                        blocker = grandchild
            verify(blocker, "expected a click-blocking MouseArea")
        }

        // ---- theme selector ----------------------------------------------

        function test_the_selected_mode_is_visibly_indicated() {
            const light = find("mode-light")
            const dark = find("mode-dark")
            verify(light.selected && light.checked)
            verify(!dark.selected && !dark.checked)
            verify(light.contentItem.text.indexOf("✓") >= 0, "check mark on the selected option")
            verify(dark.contentItem.text.indexOf("✓") < 0)
            verify(light.background.border.width > dark.background.border.width, "thicker border")
            same(light.background.border.color, Theme.primary)

            personalization.themeMode = "dark"
            verify(dark.selected && dark.checked && !light.selected && !light.checked)
            verify(dark.contentItem.text.indexOf("✓") >= 0)
        }

        function test_choosing_a_mode_emits_it_and_follows_the_setting() {
            mouseClick(find("mode-dark"))
            compare(modeSpy.count, 1)
            compare(modeSpy.signalArguments[0][0], "dark")
            // The option reflects the setting, not the click: until the owner
            // applies it, light is still the selected one.
            verify(find("mode-light").checked && !find("mode-dark").checked)
            personalization.themeMode = "dark"
            verify(find("mode-dark").checked)
        }

        function test_the_whole_ui_restyles_when_the_mode_changes() {
            const sidebar = entry(1).contentItem
            const before = Theme.background.toString()
            const sidebarTextBefore = sidebar.color.toString()
            Theme.mode = "dark"
            verify(Theme.background.toString() !== before)
            verify(sidebar.color.toString() !== sidebarTextBefore, "sidebar text follows the theme")
            verify(Theme.luminance(Theme.surface) < 0.2)
        }

        // ---- accent colors -----------------------------------------------

        function test_presets_emit_their_color() {
            const preset = Theme.accentPresets[3]
            mouseClick(find("swatch-" + preset, find("primaryChoice")))
            compare(primarySpy.count, 1)
            compare(primarySpy.signalArguments[0][0], preset)
            mouseClick(find("swatch-" + preset, find("secondaryChoice")))
            compare(secondarySpy.count, 1)
            compare(secondarySpy.signalArguments[0][0], preset)
        }

        // ---- sticky note color -------------------------------------------

        function test_the_note_color_control_offers_the_note_presets() {
            const choice = find("noteChoice")
            verify(choice, "note color control exists")
            verify(choice.visible)
            for (const preset of Theme.notePresets)
                verify(find("swatch-" + preset, choice), preset)
            verify(!find("swatch-" + Theme.accentPresets[6], choice), "not the accent colors")
        }

        function test_choosing_a_note_color_emits_it() {
            const preset = Theme.notePresets[4]
            mouseClick(find("swatch-" + preset, find("noteChoice")))
            compare(noteSpy.count, 1)
            compare(noteSpy.signalArguments[0][0], preset)
        }

        function test_the_note_swatch_in_use_is_marked_and_the_default_is_labelled() {
            const choice = find("noteChoice")
            verify(choice.isDefault)
            Theme.noteColor = Theme.notePresets[5]
            personalization.noteColor = Theme.notePresets[5]
            verify(find("swatch-" + Theme.notePresets[5], choice).selected)
            verify(!choice.isDefault)
        }

        function test_reset_note_color_is_only_enabled_for_a_custom_color() {
            const reset = find("resetNoteColor")
            verify(!reset.enabled)
            personalization.noteColor = "#bfe3ff"
            verify(reset.enabled)
            mouseClick(reset)
            compare(noteResetSpy.count, 1)
        }

        function test_a_hex_note_color_is_applied() {
            const field = find("hexField", find("noteChoice"))
            field.forceActiveFocus()
            field.text = "#abcdef"
            field.editingFinished()
            compare(noteSpy.count, 1)
            compare(noteSpy.signalArguments[0][0], "#abcdef")
        }

        function test_the_swatch_in_use_is_marked() {
            const choice = find("primaryChoice")
            verify(find("swatch-#2563eb", choice).selected, "default primary is a preset")
            verify(!find("swatch-#7c3aed", choice).selected)
            Theme.primaryColor = "#7c3aed"
            verify(find("swatch-#7c3aed", choice).selected)
            verify(!find("swatch-#2563eb", choice).selected)
        }

        function test_hex_field_shows_the_color_in_use_and_applies_valid_input() {
            const field = find("hexField", find("primaryChoice"))
            compare(field.text, "#2563eb")
            Theme.primaryColor = "#ff8800"
            compare(field.text, "#ff8800", "field follows the setting")

            field.forceActiveFocus()
            field.text = "#00aa99"
            field.editingFinished()
            compare(primarySpy.count, 1)
            compare(primarySpy.signalArguments[0][0], "#00aa99")
            verify(!field.invalid)
        }

        function test_short_hex_is_accepted() {
            const field = find("hexField", find("secondaryChoice"))
            field.text = "#0af"
            field.editingFinished()
            compare(secondarySpy.count, 1)
            compare(secondarySpy.signalArguments[0][0], "#0af")
        }

        function test_invalid_hex_is_flagged_and_not_applied() {
            const choice = find("primaryChoice")
            const field = find("hexField", choice)
            for (const bad of ["red", "#12345", "#gggggg", "", "2563eb"]) {
                field.text = bad
                field.editingFinished()
                verify(field.invalid, bad + " should be flagged")
                verify(find("hexError", choice).visible)
            }
            compare(primarySpy.count, 0, "nothing was applied")
            field.text = "#112233"
            field.textEdited()
            verify(!field.invalid, "typing clears the error")
        }

        function test_default_label_and_reset_button_reflect_custom_colors() {
            const reset = find("resetColors")
            verify(!reset.enabled, "nothing to reset")
            personalization.primaryColor = "#ff8800"
            verify(reset.enabled)
            verify(!find("primaryChoice").isDefault)
            verify(find("secondaryChoice").isDefault)
            mouseClick(reset)
            compare(resetSpy.count, 1)
            personalization.primaryColor = ""
            verify(!reset.enabled)
        }

        // ---- note style: user color or variable --------------------------

        // Scroll the page so `item` is on screen, as a user would before clicking it.
        function reveal(item) {
            let flick = item.parent
            while (flick && flick.contentY === undefined)
                flick = flick.parent
            verify(flick, "inside a scrolling page")
            const y = item.mapToItem(flick.contentItem, 0, 0).y
            flick.contentY = Math.max(0, y - 40)
        }

        function test_the_default_note_style_shows_the_user_color_controls() {
            const box = find("noteStyleBox")
            compare(box.count, 2)
            compare(box.currentValue, "user")
            compare(box.currentText, "User color")
            verify(find("userNoteControls").visible)
            verify(find("noteChoice").visible)
            verify(find("resetNoteColor").visible)
            verify(!find("paletteChoice").visible)
        }

        function test_the_variable_style_shows_the_palettes_instead() {
            personalization.noteStyle = "variable"
            const box = find("noteStyleBox")
            compare(box.currentValue, "variable")
            compare(box.currentText, "Variable")
            verify(!find("userNoteControls").visible)
            verify(!find("noteChoice").visible)
            verify(find("paletteChoice").visible)
            for (const palette of Theme.notePalettes) {
                const row = find("palette-" + palette.id)
                verify(row && row.visible, palette.id)
                compare(row.Accessible.name, palette.name)
                verify(row.activeFocusOnTab)
                compare(TestHelpers.findAllByName(row, "paletteColor").length, palette.colors.length)
            }
            personalization.noteStyle = "user"
            verify(find("noteChoice").visible)
            verify(!find("paletteChoice").visible)
        }

        function test_choosing_a_note_style_emits_it() {
            const box = find("noteStyleBox")
            box.currentIndex = 1
            box.activated(1)
            compare(styleSpy.count, 1)
            compare(styleSpy.signalArguments[0][0], "variable")
        }

        function test_choosing_a_palette_emits_it_and_the_choice_is_marked() {
            personalization.noteStyle = "variable"
            verify(find("palette-pastel").selected, "the first palette is the default")
            verify(!find("palette-candy").selected)
            reveal(find("palette-candy"))
            mouseClick(find("palette-candy"))
            compare(paletteSpy.count, 1)
            compare(paletteSpy.signalArguments[0][0], "candy")
            // The owner stores it and feeds it back.
            personalization.notePalette = "candy"
            Theme.notePalette = "candy"
            verify(find("palette-candy").selected)
            verify(!find("palette-pastel").selected)
            Theme.noteCategories = ["a"]
            Theme.noteStyle = "variable"
            same(Theme.noteColorFor("a"), Theme.paletteById("candy").colors[0])
            Theme.noteStyle = "user"
            Theme.noteCategories = []
            Theme.notePalette = ""
        }

        function test_a_palette_can_be_chosen_from_the_keyboard() {
            personalization.noteStyle = "variable"
            const row = find("palette-cool")
            row.forceActiveFocus()
            verify(row.activeFocus)
            keyClick(Qt.Key_Space)
            compare(paletteSpy.count, 1)
            compare(paletteSpy.signalArguments[0][0], "cool")
        }

        function test_an_unknown_palette_id_shows_the_first_as_selected() {
            personalization.noteStyle = "variable"
            personalization.notePalette = "gone"
            verify(find("palette-pastel").selected)
        }

        // ---- motion ------------------------------------------------------

        function test_motion_selector_shows_the_current_setting() {
            const box = find("motionBox")
            compare(box.currentValue, "system")
            personalization.motionSetting = "on"
            compare(box.currentValue, "on")
            personalization.motionSetting = "off"
            compare(box.currentValue, "off")
            compare(box.count, 3)
        }

        function test_choosing_a_motion_setting_emits_it() {
            const box = find("motionBox")
            box.currentIndex = 1
            box.activated(1)
            compare(motionSpy.count, 1)
            compare(motionSpy.signalArguments[0][0], "on")
        }
    }
}
