import QtQuick
import QtQuick.Controls
import QtTest
import StickyNotes

Item {
    id: scene
    width: 900
    height: 800

    ProjectPicker { id: picker }
    SignalSpy { id: openSpy; target: picker; signalName: "openRequested" }
    SignalSpy { id: createSpy; target: picker; signalName: "createRequested" }
    SignalSpy { id: browseSpy; target: picker; signalName: "browseRequested" }

    readonly property string two: JSON.stringify({
        root: "/data/projects",
        projects: [
            { dir: "/data/projects/a", title: "Alpha", current: false },
            { dir: "/data/projects/b", title: "Beta", current: true }
        ]
    })
    readonly property string none: JSON.stringify({ root: "/data/projects", projects: [] })

    TestCase {
        name: "ProjectPicker"
        when: windowShown

        function find(name) {
            let found = null
            const roots = [picker.contentItem, picker.footer]
            for (const root of roots)
                (function walk(item) {
                    for (const child of item.children) {
                        if (child.objectName === name) found = child
                        walk(child)
                    }
                })(root)
            return found
        }

        function init() { openSpy.clear(); createSpy.clear(); browseSpy.clear() }
        function cleanup() { picker.close() }

        function test_clicking_a_project_opens_it() {
            picker.openPicker(scene.two, false)
            tryCompare(picker, "visible", true)
            const list = find("projectList")
            tryCompare(list, "count", 2)
            wait(50)
            mouseClick(list.itemAtIndex(0))
            compare(openSpy.count, 1)
            compare(openSpy.signalArguments[0][0], "/data/projects/a")
        }

        function test_create_needs_a_name() {
            picker.openPicker(scene.two, false)
            tryCompare(picker, "visible", true)
            const create = find("createButton")
            compare(create.enabled, false)
            const field = find("nameField")
            field.text = "  New one "
            compare(create.enabled, true)
            wait(50)
            mouseClick(create)
            compare(createSpy.count, 1)
            compare(createSpy.signalArguments[0][0], "New one")
        }

        function test_enter_in_the_name_field_creates() {
            picker.openPicker(scene.none, false)
            tryCompare(picker, "visible", true)
            const field = find("nameField")
            field.text = "Fresh"
            field.forceActiveFocus()
            keyClick(Qt.Key_Return)
            compare(createSpy.count, 1)
        }

        function test_browse_is_offered() {
            picker.openPicker(scene.two, false)
            tryCompare(picker, "visible", true)
            wait(50)
            mouseClick(find("browseButton"))
            compare(browseSpy.count, 1)
        }

        function test_saving_only_offers_creating() {
            picker.openPicker(scene.two, true)
            tryCompare(picker, "visible", true)
            compare(find("projectList").visible, false)
            compare(find("browseButton").visible, false)
            compare(find("nameField").visible, true)
        }
    }
}
