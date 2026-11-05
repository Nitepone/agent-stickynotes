import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

Item {
    id: scene
    width: 900
    height: 800

    UnsavedDialog { id: unsaved }
    ConfirmDialog { id: confirm }
    AgentConnectDialog { id: agent; setupCommand: "claude mcp add x"; endpoint: "http://h:1" }

    SignalSpy { id: saveSpy; target: unsaved; signalName: "saveRequested" }
    SignalSpy { id: discardSpy; target: unsaved; signalName: "discardRequested" }

    TestCase {
        name: "Dialogs"
        when: windowShown

        function button(dialog, text) {
            const found = TestHelpers.findWhere(dialog.footer, i => i.text === text && i.visible)
            return found.length ? found[0] : null
        }
        function init() { saveSpy.clear(); discardSpy.clear() }
        function cleanup() { unsaved.close(); confirm.close(); agent.close() }

        function test_unsaved_save_hands_back_the_pending_action() {
            unsaved.pending = "next"
            unsaved.open()
            tryCompare(unsaved, "visible", true)
            wait(50)
            mouseClick(button(unsaved, "Save"))
            compare(saveSpy.count, 1)
            compare(saveSpy.signalArguments[0][0], "next")
            compare(unsaved.visible, false)
        }

        function test_unsaved_discard_hands_back_the_pending_action() {
            unsaved.pending = "later"
            unsaved.open()
            tryCompare(unsaved, "visible", true)
            wait(50)
            mouseClick(button(unsaved, "Discard"))
            compare(discardSpy.count, 1)
            compare(discardSpy.signalArguments[0][0], "later")
            compare(unsaved.visible, false)
            compare(saveSpy.count, 0)
        }

        function test_agent_dialog_shows_only_close() {
            agent.open()
            tryCompare(agent, "visible", true)
            verify(button(agent, "Close"))
            compare(button(agent, "Save"), null)
            compare(button(agent, "Cancel"), null)
        }

        function test_informational_confirm_has_no_cancel() {
            confirm.inform("t", "m")
            tryCompare(confirm, "visible", true)
            compare(button(confirm, "Cancel"), null)
            verify(button(confirm, "OK"))
            confirm.close()
            confirm.ask("t", "m", "Delete", true, () => {})
            tryCompare(confirm, "visible", true)
            verify(button(confirm, "Cancel"))
            verify(button(confirm, "Delete"))
        }
    }
}
