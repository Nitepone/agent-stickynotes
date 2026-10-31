import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes

Item {
    id: scene
    width: 900
    height: 600

    // Wednesday 2024-05-15 14:00 local time.
    readonly property real now: new Date(2024, 4, 15, 14, 0).getTime()
    function ago(days, hours) {
        return new Date(2024, 4, 15 - days, 14 - (hours || 0), 0).getTime()
    }

    readonly property var files: [
        { name: "old.md", kind: "markdown", size: 10, at: ago(60), tasks: [{ id: "t9", number: 9 }] },
        { name: "mockup.png", kind: "image", size: 10, at: ago(0, 2), tasks: [{ id: "t1", number: 1 }, { id: "t2", number: 2 }] },
        { name: "loose.md", kind: "markdown", size: 10, at: ago(3), tasks: [] },
        { name: "plan.md", kind: "markdown", size: 10, at: ago(15), tasks: [{ id: "t1", number: 1 }] },
        { name: "crowd.md", kind: "markdown", size: 10, at: ago(0, 5),
          tasks: [1, 2, 3, 4, 5, 6].map(n => ({ id: "c" + n, number: n })) },
    ]

    ArtifactsPage {
        id: page
        anchors.fill: parent
        now: scene.now
        artifacts: scene.files
    }

    SignalSpy { id: backSpy; target: page; signalName: "backRequested" }
    SignalSpy { id: fileSpy; target: page; signalName: "artifactClicked" }
    SignalSpy { id: taskSpy; target: page; signalName: "taskClicked" }

    TestCase {
        name: "ArtifactsPage"
        when: windowShown

        function init() {
            page.artifacts = scene.files
            for (const s of [backSpy, fileSpy, taskSpy]) s.clear()
        }

        function all(name) {
            const found = []
            ;(function walk(item) {
                for (const c of item.children) {
                    if (c.objectName === name && c.visible) found.push(c)
                    walk(c)
                }
            })(findChild(page, "artifactList").contentItem)
            return found.sort((a, b) => a.mapToItem(page, 0, 0).y - b.mapToItem(page, 0, 0).y)
        }

        function test_files_are_sorted_newest_first_under_dividers() {
            const names = page.entries.map(e => e.file ? e.file.name : "[" + e.header + "]")
            compare(names, ["[Today]", "mockup.png", "crowd.md", "[This week]", "loose.md",
                            "[This month]", "plan.md", "[Earlier]", "old.md"])
        }

        function test_empty_bands_get_no_divider() {
            page.artifacts = [scene.files[0]]
            compare(page.entries.map(e => e.header), ["Earlier", ""])
            page.artifacts = []
            compare(page.entries.length, 0)
            compare(findChild(page, "artifactsEmpty").visible, true)
            compare(findChild(page, "artifactList").visible, false)
        }

        function test_header_stays_at_top_when_empty() {
            const back = findChild(page, "backButton")
            const title = findChild(page, "artifactsTitle")
            const withFiles = back.mapToItem(page, 0, 0).y
            const titleWith = title.mapToItem(page, 0, 0).y
            page.artifacts = []
            wait(50)   // the layout re-polishes asynchronously
            compare(back.mapToItem(page, 0, 0).y, withFiles)
            compare(title.mapToItem(page, 0, 0).y, titleWith)
            const empty = findChild(page, "artifactsEmpty")
            verify(empty.mapToItem(page, 0, 0).y < withFiles + 100)
        }

        function test_band_edges() {
            const at = (ms) => page.build([{ name: "x.md", kind: "markdown", at: ms, tasks: [] }], scene.now)[0].header
            compare(at(new Date(2024, 4, 15, 0, 0).getTime()), "Today")
            compare(at(new Date(2024, 4, 14, 23, 59).getTime()), "This week")
            compare(at(new Date(2024, 4, 9, 0, 0).getTime()), "This week")
            compare(at(new Date(2024, 4, 8, 23, 59).getTime()), "This month")
            compare(at(new Date(2024, 3, 16, 0, 0).getTime()), "This month")
            compare(at(new Date(2024, 3, 15, 23, 59).getTime()), "Earlier")
        }

        function test_rows_show_icon_name_pills_and_date() {
            const names = all("artifactName").map(l => l.text)
            compare(names, ["mockup.png", "crowd.md", "loose.md", "plan.md", "old.md"])
            compare(all("artifactIcon").map(i => i.kind),
                    ["image", "document", "document", "document", "document"])
            const mockupPills = all("artifactPill").slice(0, 2).map(p => p.children[0].text)
            compare(mockupPills, ["#1", "#2"])
            compare(all("notAttached").length, 1)
            const dates = all("artifactDate").map(l => l.text)
            compare(dates[0], Qt.formatTime(new Date(scene.ago(0, 2)), Locale.ShortFormat))
            compare(dates[2], Qt.formatDate(new Date(scene.ago(3)), Locale.ShortFormat))
        }

        function test_only_the_first_pills_show_with_a_count_of_the_rest() {
            const more = all("morePills")
            compare(more.length, 1)
            compare(more[0].text, "+2")
            // 2 (mockup) + 4 (crowd) + 1 (plan) + 1 (old) = 8 pills in all
            compare(all("artifactPill").length, 8)
        }

        function test_clicking_a_row_opens_the_file() {
            mouseClick(all("artifactRow")[3])
            compare(fileSpy.count, 1)
            compare(fileSpy.signalArguments[0][0], "plan.md")
            compare(taskSpy.count, 0)
        }

        function test_clicking_a_pill_opens_its_task_not_the_file() {
            mouseClick(all("artifactPill")[1])
            compare(taskSpy.count, 1)
            compare(taskSpy.signalArguments[0][0], "t2")
            compare(fileSpy.count, 0)
        }

        function test_back_button_and_escape() {
            mouseClick(findChild(page, "backButton"))
            compare(backSpy.count, 1)
            page.forceActiveFocus()
            keyClick(Qt.Key_Escape)
            compare(backSpy.count, 2)
        }

        function test_the_count_is_shown() {
            compare(findChild(page, "artifactCount").text, "5 files")
            page.artifacts = [scene.files[0]]
            compare(findChild(page, "artifactCount").text, "1 file")
        }
    }
}
