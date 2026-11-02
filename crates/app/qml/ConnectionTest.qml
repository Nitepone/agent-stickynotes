import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// "Test connection" for one client section. `status` is idle, testing, ok or
// failed. The owner starts the check on `testRequested` and reports back by
// setting `status` and `message`. A success shows "Connected"; a failure shows
// the error and a Retry button.
ColumnLayout {
    id: root

    property string status: "idle"
    property string message: ""

    signal testRequested()

    Layout.fillWidth: true
    spacing: 4

    RowLayout {
        spacing: 8
        Button {
            objectName: "testButton"
            visible: root.status === "idle" || root.status === "testing"
            enabled: root.status !== "testing"
            text: root.status === "testing" ? qsTr("Testing…") : qsTr("Test connection")
            onClicked: root.testRequested()
        }
        Button {
            objectName: "retryButton"
            visible: root.status === "failed"
            text: qsTr("Retry")
            onClicked: root.testRequested()
        }
        Label {
            objectName: "connectedLabel"
            visible: root.status === "ok"
            text: qsTr("Connected")
            font.bold: true
            color: Theme.success
            Accessible.role: Accessible.StaticText
            Accessible.name: qsTr("Connected")
        }
    }
    Label {
        Layout.fillWidth: true
        visible: root.status === "idle" || root.status === "ok"
        wrapMode: Text.Wrap
        color: Theme.subtleText
        text: qsTr("Checks that the app's agent endpoint is reachable and the token is accepted. It cannot see whether this client's configuration is correct.")
    }
    ErrorLabel {
        objectName: "errorLabel"
        text: root.status === "failed" ? root.message : ""
    }
}
