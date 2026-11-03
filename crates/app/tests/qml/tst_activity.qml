import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

Item {
    id: scene
    width: 900
    height: 700

    ActivityDialog { id: dlg }

    readonly property string fixture: JSON.stringify({ days: [
        { label: "Today", summary: "Today: 2 changes by claude-code on 1 task: 1 created, 1 advanced",
          entries: [ { time: "10:42", text: "claude-code advanced #12 to Review" },
                     { time: "10:40", text: "claude-code created #12" } ] },
        { label: "Yesterday", summary: "Yesterday: 1 change by claude-code on 1 task: 1 updated",
          entries: [ { time: "09:00", text: "claude-code updated #3" } ] } ] })

    TestCase {
        name: "Activity"
        when: windowShown

        function cleanup() { dlg.close() }
        function all(name) {
            const out = []
            const walk = (item) => {
                if (item.objectName === name) out.push(item)
                for (const c of item.children) walk(c)
            }
            walk(dlg.contentItem.contentItem)
            return out
        }

        function test_summary_and_entries() {
            dlg.activityJson = scene.fixture
            dlg.open()
            tryCompare(dlg, "opened", true)
            const sums = all("daySummary")
            compare(sums.length, 2)
            verify(sums[0].text.indexOf("Today: 2 changes by claude-code on 1 task") === 0)
            const entries = all("activityEntry")
            compare(entries.length, 3)
            compare(entries[0].text, "claude-code advanced #12 to Review")
            compare(all("activityEmpty")[0].visible, false)
        }

        function test_empty_state() {
            dlg.activityJson = "{\"days\":[]}"
            dlg.open()
            tryCompare(dlg, "opened", true)
            compare(all("activityEmpty")[0].visible, true)
            compare(all("daySummary").length, 0)
        }
    }
}
