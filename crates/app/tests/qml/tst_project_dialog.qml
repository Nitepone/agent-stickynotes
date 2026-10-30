import QtQuick
import QtQuick.Controls
import QtTest
import StickyNotes

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
            const roots = [dialog.contentItem, dialog.footer]
            for (const root of roots)
                (function walk(item) {
                    for (const child of item.children) {
                        if (child.objectName === name) found = child
                        walk(child)
                    }
                })(root)
            return found
        }

        function init() { saveSpy.clear(); artifactSpy.clear() }
        function cleanup() { dialog.close() }

        function test_loads_current_settings() {
            dialog.openProject(JSON.stringify({
                title: "T", documentPrompt: "Be brief.", codeGuidance: "Use Rust." }))
            tryCompare(dialog, "visible", true)
            compare(find("documentField").text, "Be brief.")
            compare(find("codeField").text, "Use Rust.")
        }

        function findAll(name) {
            const found = []
            ;(function walk(item) {
                for (const child of item.children) {
                    if (child.objectName === name) found.push(child)
                    walk(child)
                }
            })(dialog.contentItem)
            return found
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

        function test_save_emits_both_texts() {
            dialog.openProject(JSON.stringify({ title: "T", documentPrompt: "", codeGuidance: "" }))
            tryCompare(dialog, "visible", true)
            find("documentField").text = "New doc prompt"
            find("codeField").text = "New code guidance\nsecond line"
            mouseClick(find("saveProject"))
            compare(saveSpy.count, 1)
            compare(saveSpy.signalArguments[0][0], "New doc prompt")
            compare(saveSpy.signalArguments[0][1], "New code guidance\nsecond line")
        }

        function test_cancel_discards_edits() {
            dialog.openProject(JSON.stringify({ title: "T", documentPrompt: "keep", codeGuidance: "" }))
            tryCompare(dialog, "visible", true)
            find("documentField").text = "edited"
            dialog.close()
            dialog.openProject(JSON.stringify({ title: "T", documentPrompt: "keep", codeGuidance: "" }))
            compare(find("documentField").text, "keep")
            compare(saveSpy.count, 0)
        }
    }
}
