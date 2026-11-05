import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Preferences > About: the application name and version, and the port of
// this board's agent server.
PreferencesSection {
    title: qsTr("About")

    property string version: ""
    property int agentPort: 0

    ColumnLayout {
        x: Theme.px(32)
        y: Theme.px(24)
        spacing: Theme.px(8)

        Label {
            text: qsTr("About")
            font.pixelSize: Theme.fs(22)
            font.bold: true
            color: Theme.text
        }
        Label {
            text: qsTr("Agent Stickynotes")
            font.pixelSize: Theme.fs(16)
            color: Theme.text
        }
        Label {
            objectName: "versionLabel"
            text: qsTr("Version %1").arg(version)
            color: Theme.text
            Accessible.name: text
        }
        Label {
            objectName: "agentPortLabel"
            visible: agentPort > 0
            text: qsTr("Agent server port: %1").arg(agentPort)
            color: Theme.text
            Accessible.name: text
        }
    }
}
