import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Preferences > About: the application name and version.
PreferencesSection {
    title: qsTr("About")

    property string version: ""

    ColumnLayout {
        x: 32
        y: 24
        spacing: 8

        Label {
            text: qsTr("About")
            font.pixelSize: 22
            font.bold: true
            color: Theme.text
        }
        Label {
            text: qsTr("Agent Stickynotes")
            font.pixelSize: 16
            color: Theme.text
        }
        Label {
            objectName: "versionLabel"
            text: qsTr("Version %1").arg(version)
            color: Theme.text
            Accessible.name: text
        }
    }
}
