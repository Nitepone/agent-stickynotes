import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

Item {
    id: scene
    width: 900
    height: 900

    AgentConnectDialog {
        id: dlg
        setupCommand: "claude mcp add stickynotes"
        desktopProjectJson: "{ \"desktop\": 1 }"
        desktopBridgeJson: "{ \"bridge\": 1 }"
        opencodeJson: "{ \"opencode\": 1 }"
        endpoint: "http://h:1"
        port: 40123
        reducedMotion: true
    }
    // Never touched, to check the defaults.
    AgentConnectDialog { id: pristine }
    SignalSpy { id: testSpy; target: dlg; signalName: "testRequested" }

    TestCase {
        name: "AgentConnect"
        when: windowShown

        function init() {
            testSpy.clear()
            // Sections are set by hand in some tests; start each from the defaults.
            for (const [s, on] of [["cliSection", true], ["desktopSection", false], ["opencodeSection", false]])
                named(s).expanded = on
            dlg.open()
            tryCompare(dlg, "opened", true)
        }
        function cleanup() { dlg.close() }

        function named(n) { return TestHelpers.findByName(dlg.contentItem, n) }

        function test_the_dialog_names_this_boards_port() {
            const label = named("portLabel")
            verify(label.visible)
            verify(label.text.indexOf("port 40123") >= 0, label.text)
            verify(!TestHelpers.findByName(pristine.contentItem, "portLabel").visible,
                   "no port line before the port is known")
        }
        function header(section) { return TestHelpers.findByName(named(section), "sectionHeader") }
        function inSection(section, n) { return TestHelpers.findByName(named(section), n) }
        // Scroll the dialog's content so `item` is in view, then click it.
        function clickItem(item) {
            const flick = dlg.contentItem.contentItem
            const y = item.mapToItem(flick.contentItem, 0, 0).y
            flick.contentY = Math.max(0, Math.min(y - 20, flick.contentHeight - flick.height))
            wait(20)
            mouseClick(item)
        }
        function isShown(item) { return item !== null && item.visible }
        function expanded() {
            return ["cliSection", "desktopSection", "opencodeSection"].map(s => named(s).expanded)
        }

        function test_default_is_cli_expanded_others_collapsed() {
            pristine.open()
            tryCompare(pristine, "opened", true)
            const got = ["cliSection", "desktopSection", "opencodeSection"]
                .map(s => TestHelpers.findByName(pristine.contentItem, s).expanded)
            pristine.close()
            compare(got, [true, false, false])
            compare(expanded(), [true, false, false])
            verify(isShown(inSection("cliSection", "cliCommand")))
            verify(!isShown(inSection("desktopSection", "desktopProjectJson")))
            verify(!isShown(inSection("opencodeSection", "opencodeJson")))
        }

        function test_sections_toggle_independently() {
            clickItem(header("desktopSection"))
            compare(expanded(), [true, true, false])
            clickItem(header("opencodeSection"))
            compare(expanded(), [true, true, true])
            clickItem(header("cliSection"))
            compare(expanded(), [false, true, true])
            clickItem(header("desktopSection"))
            compare(expanded(), [false, false, true])
        }

        function test_keyboard_toggles() {
            const h = header("opencodeSection")
            h.forceActiveFocus()
            verify(h.activeFocus)
            keyClick(Qt.Key_Space)
            compare(named("opencodeSection").expanded, true)
            keyClick(Qt.Key_Return)
            compare(named("opencodeSection").expanded, false)
            compare(named("cliSection").expanded, true)
        }

        function test_header_is_accessible() {
            const h = header("cliSection")
            compare(h.Accessible.role, Accessible.Button)
            compare(h.Accessible.name, "Claude Code CLI")
            verify(h.activeFocusOnTab)
        }

        function test_each_section_shows_only_its_own_steps() {
            for (const s of ["cliSection", "desktopSection", "opencodeSection"])
                named(s).expanded = true
            compare(inSection("cliSection", "cliCommand").text, "claude mcp add stickynotes")
            verify(inSection("cliSection", "desktopProjectJson") === null)
            verify(inSection("cliSection", "opencodeJson") === null)
            compare(inSection("desktopSection", "desktopProjectJson").text, dlg.desktopProjectJson)
            compare(inSection("desktopSection", "desktopBridgeJson").text, dlg.desktopBridgeJson)
            verify(inSection("desktopSection", "cliCommand") === null)
            verify(inSection("desktopSection", "opencodeJson") === null)
            compare(inSection("opencodeSection", "opencodeJson").text, dlg.opencodeJson)
            verify(inSection("opencodeSection", "cliCommand") === null)
            verify(inSection("opencodeSection", "desktopProjectJson") === null)
        }

        function test_desktop_section_does_not_mention_the_cli() {
            const texts = TestHelpers.findWhere(named("desktopSection"), i => typeof i.text === "string" && i.text !== "", true)
                .map(i => i.text).join("\n")
            verify(texts.indexOf("claude mcp") < 0)
            verify(texts.indexOf("terminal") < 0)
            verify(texts.indexOf("CLI") < 0)
        }

        function test_success_confirms_only_in_that_section() {
            for (const s of ["cliSection", "desktopSection", "opencodeSection"])
                named(s).expanded = true
            clickItem(inSection("desktopSection", "testButton"))
            compare(testSpy.count, 1)
            compare(testSpy.signalArguments[0][0], "desktop")
            compare(named("desktopTest").status, "testing")
            dlg.setCheckResult("desktop", true, "")
            verify(isShown(inSection("desktopSection", "connectedLabel")))
            verify(!isShown(inSection("cliSection", "connectedLabel")))
            verify(!isShown(inSection("opencodeSection", "connectedLabel")))
            verify(!isShown(inSection("desktopSection", "retryButton")))
        }

        function test_failure_shows_error_and_retry_only_in_that_section() {
            for (const s of ["cliSection", "desktopSection", "opencodeSection"])
                named(s).expanded = true
            clickItem(inSection("opencodeSection", "testButton"))
            dlg.setCheckResult("opencode", false, "token rejected")
            const err = inSection("opencodeSection", "errorLabel")
            verify(isShown(err))
            compare(err.text, "token rejected")
            verify(isShown(inSection("opencodeSection", "retryButton")))
            verify(!isShown(inSection("opencodeSection", "connectedLabel")))
            verify(!isShown(inSection("cliSection", "errorLabel")))
            verify(!isShown(inSection("cliSection", "retryButton")))
            verify(!isShown(inSection("desktopSection", "retryButton")))
        }

        function test_retry_runs_the_check_again_and_can_succeed() {
            clickItem(inSection("cliSection", "testButton"))
            dlg.setCheckResult("cli", false, "unreachable")
            testSpy.clear()
            clickItem(inSection("cliSection", "retryButton"))
            compare(testSpy.count, 1)
            compare(testSpy.signalArguments[0][0], "cli")
            compare(named("cliTest").status, "testing")
            dlg.setCheckResult("cli", true, "")
            verify(isShown(inSection("cliSection", "connectedLabel")))
            verify(!isShown(inSection("cliSection", "errorLabel")))
        }

        function test_reopening_clears_results() {
            dlg.setCheckResult("cli", false, "x")
            dlg.close()
            dlg.open()
            tryCompare(dlg, "opened", true)
            compare(named("cliTest").status, "idle")
        }
    }
}
