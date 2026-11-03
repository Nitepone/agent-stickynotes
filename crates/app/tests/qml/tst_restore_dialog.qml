import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

Item {
    id: scene
    width: 900
    height: 800

    RestoreDialog { id: dlg }
    SignalSpy { id: restoreSpy; target: dlg; signalName: "restoreRequested" }

    readonly property string sample: JSON.stringify([
        { name: "board-20260101-121100.json", time: "2026-01-01 12:11:00", tasks: 3, readable: true, isBak: false },
        { name: "board-20260101-120000.json", time: "2026-01-01 12:00:00", tasks: null, readable: false, isBak: false },
        { name: "board.json.bak", time: "2026-01-01 11:00:00", tasks: 1, readable: true, isBak: true }
    ])

    TestCase {
        name: "RestoreDialog"
        when: windowShown

        function init() {
            restoreSpy.clear()
            dlg.openWith(scene.sample)
            tryCompare(dlg, "opened", true)
            wait(50)
        }
        function cleanup() { dlg.close() }

        function rows() { return TestHelpers.findAllByName(dlg.contentItem, "backupRow") }
        function restoreButton() { return TestHelpers.findByName(dlg.footer, "restoreButton") }

        function test_lists_backups_with_time_and_task_count() {
            const r = rows()
            compare(r.length, 3)
            verify(r[0].text.indexOf("2026-01-01 12:11:00") >= 0)
            verify(r[0].text.indexOf("3 task") >= 0)
            verify(r[2].text.indexOf("before last save") >= 0)
        }

        function test_unreadable_backup_is_disabled_and_cannot_be_chosen() {
            const bad = rows()[1]
            verify(bad.text.indexOf("unreadable") >= 0)
            compare(bad.enabled, false)
            mouseClick(bad)
            compare(dlg.selected, "")
            compare(restoreButton().enabled, false)
        }

        function test_restores_only_after_confirmation() {
            mouseClick(rows()[0])
            compare(dlg.selected, "board-20260101-121100.json")
            mouseClick(restoreButton())
            compare(restoreSpy.count, 0)
            compare(dlg.confirming, true)
            verify(TestHelpers.findByName(dlg.contentItem, "confirmText").visible)
            mouseClick(restoreButton())
            compare(restoreSpy.count, 1)
            compare(restoreSpy.signalArguments[0][0], "board-20260101-121100.json")
            compare(dlg.visible, false)
        }

        function test_choosing_another_backup_drops_the_confirmation() {
            mouseClick(rows()[0])
            mouseClick(restoreButton())
            compare(dlg.confirming, true)
            mouseClick(rows()[2])
            compare(dlg.confirming, false)
            compare(restoreSpy.count, 0)
        }

        function test_empty_list_says_so() {
            dlg.close()
            dlg.openWith("[]")
            tryCompare(dlg, "opened", true)
            verify(TestHelpers.findByName(dlg.contentItem, "noBackups").visible)
        }
    }
}
