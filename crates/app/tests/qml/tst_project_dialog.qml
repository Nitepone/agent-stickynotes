import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

Item {
    id: scene
    width: 900
    height: 800

    ProjectDialog { id: dialog }
    SignalSpy { id: saveSpy; target: dialog; signalName: "saveRequested" }
    SignalSpy { id: artifactSpy; target: dialog; signalName: "artifactClicked" }

    TestCase {
        name: "ProjectDialog"
        when: windowShown

        function find(name) {
            let found = null
            for (const root of [dialog.contentItem, dialog.footer])
                found = TestHelpers.findByName(root, name) || found
            return found
        }

        function init() { saveSpy.clear(); artifactSpy.clear() }
        function cleanup() { dialog.close() }

        function test_loads_current_settings() {
            dialog.openProject(JSON.stringify({
                title: "T", documentPrompt: "Be brief.", codeGuidance: "Use Rust." }))
            tryCompare(dialog, "visible", true)
            compare(find("nameField").text, "T")
            compare(find("documentField").text, "Be brief.")
            compare(find("codeField").text, "Use Rust.")
            verify(find("documentField").activeFocus, "the menu starts in the instructions")
        }

        function test_opening_from_the_title_selects_the_name() {
            dialog.openProject(JSON.stringify({ title: "Launch", documentPrompt: "", codeGuidance: "" }), true)
            tryCompare(dialog, "visible", true)
            const name = find("nameField")
            tryCompare(name, "activeFocus", true)
            compare(name.selectedText, "Launch")
            keyClick(Qt.Key_N)
            compare(name.text, "n", "typing replaces the name")
        }

        function test_an_empty_name_is_refused_inline() {
            dialog.openProject(JSON.stringify({ title: "T", documentPrompt: "", codeGuidance: "" }))
            tryCompare(dialog, "visible", true)
            find("nameField").text = "   "
            mouseClick(find("saveProject"))
            compare(saveSpy.count, 0)
            verify(dialog.errorText.length > 0)
            verify(find("nameField").invalid)
            compare(dialog.visible, true)
        }

        function findAll(name) {
            return TestHelpers.findAllByName(dialog.contentItem, name)
        }

        function test_lists_every_artifact_with_the_tasks_it_is_attached_to() {
            dialog.openProject(JSON.stringify({
                title: "T", documentPrompt: "", codeGuidance: "",
                artifacts: [
                    { name: "plan.md", kind: "markdown", size: 10, tasks: [3, 12] },
                    { name: "old.png", kind: "image", size: 99, tasks: [] },
                ] }))
            tryCompare(dialog, "visible", true)
            waitForRendering(dialog.contentItem)
            const links = findAll("artifactLink")
            compare(links.map(l => l.text), ["plan.md", "old.png"])
            compare(findAll("artifactTasks").map(l => l.text), ["#3, #12", "not attached"])
            links[1].clicked()
            compare(artifactSpy.signalArguments[0][0], "old.png")
        }

        function test_a_project_without_artifacts_loads() {
            dialog.openProject(JSON.stringify({ title: "T", documentPrompt: "", codeGuidance: "" }))
            tryCompare(dialog, "visible", true)
            compare(findAll("artifactLink").length, 0)
        }

        function test_save_emits_the_name_and_both_texts() {
            dialog.openProject(JSON.stringify({ title: "T", documentPrompt: "", codeGuidance: "" }))
            tryCompare(dialog, "visible", true)
            find("nameField").text = "Renamed"
            find("documentField").text = "New doc prompt"
            find("codeField").text = "New code guidance\nsecond line"
            mouseClick(find("saveProject"))
            compare(saveSpy.count, 1)
            compare(saveSpy.signalArguments[0][0], "Renamed")
            compare(saveSpy.signalArguments[0][1], "New doc prompt")
            compare(saveSpy.signalArguments[0][2], "New code guidance\nsecond line")
        }

        function test_cancel_discards_edits() {
            dialog.openProject(JSON.stringify({ title: "T", documentPrompt: "keep", codeGuidance: "" }))
            tryCompare(dialog, "visible", true)
            find("nameField").text = "edited name"
            find("documentField").text = "edited"
            dialog.close()
            dialog.openProject(JSON.stringify({ title: "T", documentPrompt: "keep", codeGuidance: "" }))
            compare(find("nameField").text, "T")
            compare(find("documentField").text, "keep")
            compare(saveSpy.count, 0)
        }
    }
}
