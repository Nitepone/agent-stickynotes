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
    SignalSpy { id: endpointSpy; target: editor; signalName: "ollamaEndpointChosen" }
    SignalSpy { id: tokenSpy; target: editor; signalName: "ollamaTokenChosen" }
    SignalSpy { id: testSpy; target: editor; signalName: "testConnectionRequested" }

    TestCase {
        name: "EditorSection"
        when: windowShown

        function init() {
            for (const spy of [spellSpy, agentSpy, promptSpy, modelSpy, effortSpy, endpointSpy, tokenSpy, testSpy])
                spy.clear()
            page.currentIndex = 1
            editor.spellCheck = true
            editor.spellAvailable = true
            editor.draftAgent = "claude_code"
            editor.draftSystemPrompt = ""
            editor.draftModel = ""
            editor.draftEffort = ""
            editor.ollamaEndpoint = "http://localhost:11434"
            editor.ollamaToken = ""
            editor.ollamaEndpointInvalid = false
            editor.testState = "idle"
            editor.testStale = false
            editor.testMessage = ""
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

        function test_agent_type_offers_claude_code_and_ollama() {
            const box = find("agentBox")
            compare(box.count, 2)
            compare(box.currentValue, "claude_code")
            compare(box.currentText, "Claude Code (subshell)")
            choose(box, 1)
            compare(agentSpy.count, 1)
            compare(agentSpy.signalArguments[0][0], "ollama")
            editor.draftAgent = "ollama"
            compare(box.currentValue, "ollama")
        }

        function test_ollama_fields_show_only_when_ollama_is_selected() {
            verify(!find("ollamaOptions").visible)
            verify(find("claudeCodeOptions").visible)
            editor.draftAgent = "ollama"
            verify(find("ollamaOptions").visible)
            verify(!find("claudeCodeOptions").visible)
            verify(find("endpointField").visible && find("tokenField").visible)
        }

        function test_the_token_is_masked_and_optional() {
            editor.draftAgent = "ollama"
            editor.ollamaToken = "s3cret"
            const field = find("tokenField")
            compare(field.echoMode, TextInput.Password)
            compare(field.text, "s3cret")
            compare(field.displayText.indexOf("s3cret"), -1, "the characters are not displayed")
            compare(tokenSpy.count, 0)
            field.forceActiveFocus()
            field.text = ""
            field.editingFinished()
            compare(tokenSpy.count, 1)
            compare(tokenSpy.signalArguments[0][0], "", "an empty token clears it")
        }

        function test_endpoint_token_and_model_are_reported() {
            editor.draftAgent = "ollama"
            compare(find("endpointField").text, "http://localhost:11434")
            let field = find("endpointField")
            field.forceActiveFocus()
            field.text = "https://llm.example.com"
            field.editingFinished()
            compare(endpointSpy.count, 1)
            compare(endpointSpy.signalArguments[0][0], "https://llm.example.com")

            field = find("tokenField")
            field.forceActiveFocus()
            field.text = "abc"
            field.editingFinished()
            compare(tokenSpy.count, 1)
            compare(tokenSpy.signalArguments[0][0], "abc")

            field = find("ollamaModelField")
            field.forceActiveFocus()
            field.text = "llama3.2"
            field.editingFinished()
            compare(modelSpy.count, 1)
            compare(modelSpy.signalArguments[0][0], "llama3.2")
        }

        function test_unchanged_fields_report_nothing_and_a_rejected_endpoint_is_flagged() {
            editor.draftAgent = "ollama"
            const field = find("endpointField")
            field.forceActiveFocus()
            field.editingFinished()
            compare(endpointSpy.count, 0)
            verify(!find("endpointError").visible)
            editor.ollamaEndpointInvalid = true
            verify(find("endpointError").visible)
            field.textEdited()
            verify(!field.invalid, "typing clears the flag")
        }

        function test_stored_ollama_values_are_shown() {
            editor.draftAgent = "ollama"
            editor.ollamaEndpoint = "http://box:8080"
            editor.draftModel = "qwen3"
            compare(find("endpointField").text, "http://box:8080")
            compare(find("ollamaModelField").text, "qwen3")
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

        // ---- test connection ---------------------------------------------

        function test_the_test_button_is_only_there_for_the_ollama_agent() {
            const button = find("testConnectionButton")
            verify(!button.visible)
            editor.draftAgent = "ollama"
            verify(button.visible)
            const y = (name) => find(name).mapToItem(editor, 0, 0).y
            tryVerify(() => Math.abs(y("testConnectionButton") - y("endpointField")) < 12,
                      1000, "next to the endpoint field")
            verify(button.mapToItem(editor, 0, 0).x > find("endpointField").mapToItem(editor, 0, 0).x)
            editor.draftAgent = "claude_code"
            verify(!button.visible)
        }

        function test_clicking_asks_the_owner_and_is_disabled_while_running() {
            editor.draftAgent = "ollama"
            const button = find("testConnectionButton")
            mouseClick(button)
            compare(testSpy.count, 1)
            compare(editor.testState, "testing")
            verify(!button.enabled)
            compare(button.text, "Testing\u2026")
            mouseClick(button)
            compare(testSpy.count, 1, "no second request while one runs")
        }

        function test_a_success_is_shown_and_the_button_works_again() {
            editor.draftAgent = "ollama"
            mouseClick(find("testConnectionButton"))
            editor.setTestResult(true, null, undefined)
            verify(find("testOkLabel").visible)
            compare(find("testOkLabel").text, "Connected")
            verify(!find("testErrorLabel").visible)
            verify(find("testConnectionButton").enabled)
            mouseClick(find("testConnectionButton"))
            compare(testSpy.count, 2)
            verify(!find("testOkLabel").visible, "a new run clears the old result")
        }

        function test_a_success_with_a_note_shows_the_note() {
            editor.draftAgent = "ollama"
            mouseClick(find("testConnectionButton"))
            editor.setTestResult(true, "Connected. Model 'x' was not listed by the server.", undefined)
            verify(find("testOkLabel").visible)
            compare(find("testOkLabel").text, "Connected. Model 'x' was not listed by the server.")
            verify(!find("testErrorLabel").visible)
        }

        function test_a_failure_shows_the_message() {
            editor.draftAgent = "ollama"
            mouseClick(find("testConnectionButton"))
            editor.setTestResult(false, null, "The server rejected the auth token.")
            verify(find("testErrorLabel").visible)
            compare(find("testErrorLabel").text, "The server rejected the auth token.")
            verify(!find("testOkLabel").visible)
            verify(find("testConnectionButton").enabled, "can retry")
        }

        function test_a_stale_result_is_cleared_when_the_settings_change() {
            editor.draftAgent = "ollama"
            const changes = [
                () => editor.ollamaEndpoint = "http://other:1",
                () => editor.ollamaToken = "t",
                () => editor.draftModel = "m",
                () => { editor.draftAgent = "claude_code"; editor.draftAgent = "ollama" }
            ]
            for (const change of changes) {
                editor.testState = "failed"
                editor.testMessage = "boom"
                change()
                compare(editor.testState, "idle")
                verify(!find("testErrorLabel").visible)
            }
        }

        function test_a_result_for_changed_settings_is_dropped() {
            editor.draftAgent = "ollama"
            mouseClick(find("testConnectionButton"))
            editor.ollamaEndpoint = "http://other:1"
            compare(editor.testState, "testing", "still waiting for the run")
            editor.setTestResult(true, null, undefined)
            compare(editor.testState, "idle")
            verify(!find("testOkLabel").visible)
            verify(find("testConnectionButton").enabled)
        }

        function test_clicking_saves_pending_edits_before_asking() {
            editor.draftAgent = "ollama"
            const field = find("endpointField")
            field.forceActiveFocus()
            field.text = "http://typed:1"
            mouseClick(find("testConnectionButton"))
            compare(endpointSpy.count, 1)
            compare(endpointSpy.signalArguments[0][0], "http://typed:1")
            compare(testSpy.count, 1)
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
