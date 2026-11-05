import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

Item {
    width: 900
    height: 600

    PreferencesPage {
        id: page
        anchors.fill: parent
        PreferencesSection { title: "First" }
        AboutSection { id: about; version: "1.2.3"; agentPort: 7317 }
    }

    TestCase {
        name: "About"
        when: windowShown

        function test_about_is_in_the_sidebar_and_shows_the_version() {
            const entry = TestHelpers.findByName(page, "sidebarItem1")
            compare(entry.text, "About")
            mouseClick(entry)
            const label = TestHelpers.findByName(page, "versionLabel")
            verify(label.visible)
            compare(label.text, "Version 1.2.3")
            const port = TestHelpers.findByName(page, "agentPortLabel")
            verify(port.visible)
            compare(port.text, "Agent server port: 7317")
        }
    }
}
