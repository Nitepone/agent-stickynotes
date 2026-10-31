import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

Item {
    id: scene
    width: 1000
    height: 760

    PreferencesPage {
        id: page
        anchors.fill: parent

        PersonalizationSection { id: personalization }
        EditorSection { id: editor; objectName: "editor" }
    }

    SignalSpy { id: spellSpy; target: editor; signalName: "spellCheckChosen" }
    SignalSpy { id: agentSpy; target: editor; signalName: "draftAgentChosen" }
    SignalSpy { id: promptSpy; target: editor; signalName: "draftSystemPromptChosen" }
    SignalSpy { id: modelSpy; target: editor; signalName: "draftModelChosen" }
    SignalSpy { id: effortSpy; target: editor; signalName: "draftEffortChosen" }

    TestCase {
        name: "EditorSection"
        when: windowShown

        function init() {
            for (const spy of [spellSpy, agentSpy, promptSpy, modelSpy, effortSpy])
                spy.clear()
            page.currentIndex = 1
            editor.spellCheck = true
            editor.spellAvailable = true
            editor.draftAgent = "claude_code"
            editor.draftSystemPrompt = ""
            editor.draftModel = ""
            editor.draftEffort = ""
        }

        function find(name) {
            return TestHelpers.findByName(editor, name)
        }

        function choose(box, index) {
            box.popup.open()
            tryCompare(box.popup, "visible", true)
            const item = box.popup.contentItem.itemAtIndex
                ? box.popup.contentItem.itemAtIndex(index) : null
            verify(item, "popup entry " + index)
            mouseClick(item)
            tryCompare(box.popup, "visible", false)
        }

        // ---- the page ----------------------------------------------------

        function test_the_editor_page_is_in_the_sidebar_and_can_be_opened() {
            compare(page.sectionCount, 2)
            const entry = TestHelpers.findByName(page, "sidebarItem1")
            compare(entry.text, "Editor")
            page.currentIndex = 0
            verify(!editor.visible)
            mouseClick(entry)
            compare(page.currentIndex, 1)
            verify(editor.visible)
        }

        // ---- spell check -------------------------------------------------

        function test_spell_check_checkbox_shows_the_setting() {
            verify(find("spellCheckBox").checked)
            editor.spellCheck = false
            verify(!find("spellCheckBox").checked)
        }

        function test_toggling_spell_check_reports_the_new_state_and_follows_the_owner() {
            mouseClick(find("spellCheckBox"))
            compare(spellSpy.count, 1)
            compare(spellSpy.signalArguments[0][0], false)
            verify(find("spellCheckBox").checked, "shows the stored setting until the owner applies it")
            editor.spellCheck = false
            verify(!find("spellCheckBox").checked)
            mouseClick(find("spellCheckBox"))
            compare(spellSpy.signalArguments[1][0], true)
        }

        function test_a_missing_dictionary_is_explained() {
            verify(!find("noDictionary").visible)
            editor.spellAvailable = false
            verify(find("noDictionary").visible)
        }

        // ---- draft agent -------------------------------------------------

        function test_agent_type_lists_only_claude_code() {
            const box = find("agentBox")
            compare(box.count, 1)
            compare(box.currentValue, "claude_code")
            compare(box.currentText, "Claude Code (subshell)")
        }

        function test_claude_code_options_show_for_claude_code() {
            const options = find("claudeCodeOptions")
            verify(options.visible)
            verify(find("modelBox").visible && find("effortBox").visible)
            verify(find("promptField").visible)
            editor.draftAgent = "something_else"
            verify(!options.visible, "agent-specific options follow the agent type")
            verify(find("promptField").visible, "the system prompt is for every type")
        }

        function test_options_are_below_the_agent_type() {
            // init() just changed what is visible; a layout is rearranged on the
            // next polish, not immediately, so wait for it instead of reading
            // positions that are still from the previous test.
            const y = (name) => find(name).mapToItem(editor, 0, 0).y
            const type = () => y("agentBox")
            tryVerify(() => y("promptField") > type())
            tryVerify(() => y("modelBox") > type())
            tryVerify(() => y("effortBox") > type())
        }

        function test_stored_choices_are_shown() {
            editor.draftModel = "sonnet"
            editor.draftEffort = "high"
            editor.draftSystemPrompt = "Be brief."
            compare(find("modelBox").currentValue, "sonnet")
            compare(find("effortBox").currentValue, "high")
            compare(find("promptField").text, "Be brief.")
        }

        function test_the_box_follows_the_stored_setting_after_a_pick() {
            editor.draftModel = "opus"
            choose(find("modelBox"), 3)
            compare(modelSpy.count, 1)
            compare(modelSpy.signalArguments[0][0], "sonnet")
            compare(find("modelBox").currentValue, "sonnet", "shows the pick")
            // Later changes to the stored setting still reach the box.
            editor.draftModel = "haiku"
            compare(find("modelBox").currentValue, "haiku")
            editor.draftModel = ""
            compare(find("modelBox").currentValue, "")
        }

        function test_thinking_level_is_reported() {
            choose(find("effortBox"), 4)
            compare(effortSpy.count, 1)
            compare(effortSpy.signalArguments[0][0], "xhigh")
        }

        function test_values_stored_before_the_page_exists_are_shown() {
            // What happens at startup: the section is created with the stored settings.
            const fresh = Qt.createQmlObject(
                'import QtQuick; import StickyNotes; EditorSection { width: 600; height: 600; draftModel: "opus"; draftEffort: "high"; draftAgent: "claude_code" }',
                scene)
            const box = (name) => TestHelpers.findByName(fresh, name)
            compare(box("modelBox").currentValue, "opus")
            compare(box("effortBox").currentValue, "high")
            fresh.destroy()
        }

        function test_unknown_stored_values_show_the_default() {
            editor.draftModel = "no-such-model"
            compare(find("modelBox").currentIndex, 0)
        }

        // ---- system prompt -----------------------------------------------

        function test_the_prompt_is_saved_once_typing_stops() {
            const field = find("promptField")
            field.forceActiveFocus()
            field.text = "Write in British English."
            compare(promptSpy.count, 0, "not on every keystroke")
            tryCompare(promptSpy, "count", 1, 3000)
            compare(promptSpy.signalArguments[0][0], "Write in British English.")
        }

        function test_the_prompt_is_saved_when_the_field_loses_focus() {
            const field = find("promptField")
            field.forceActiveFocus()
            field.text = "Short items."
            find("spellCheckBox").forceActiveFocus()
            compare(promptSpy.count, 1)
            compare(promptSpy.signalArguments[0][0], "Short items.")
        }

        function test_the_prompt_is_saved_when_the_page_is_left() {
            const field = find("promptField")
            field.forceActiveFocus()
            field.text = "Leave now."
            page.currentIndex = 0
            compare(promptSpy.count, 1)
            compare(promptSpy.signalArguments[0][0], "Leave now.")
        }

        function test_an_unchanged_prompt_is_not_saved_again() {
            editor.draftSystemPrompt = "Same."
            const field = find("promptField")
            field.forceActiveFocus()
            find("spellCheckBox").forceActiveFocus()
            compare(promptSpy.count, 0)
        }
    }
}
