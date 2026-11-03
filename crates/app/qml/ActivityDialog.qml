import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// What agents changed on the board, per day: a summary line, then that day's
// entries newest first. The owner supplies `activityJson` (built by the core);
// this dialog only displays it.
StickyDialog {
    id: dialog

    property string activityJson: "{\"days\":[]}"
    readonly property var days: {
        try { return JSON.parse(activityJson).days || [] } catch (e) { return [] }
    }

    title: qsTr("Agent Activity")
    maxWidth: 720
    acceptText: ""
    rejectText: qsTr("Close")

    contentItem: ScrollView {
        id: scroll
        implicitHeight: Math.min(column.implicitHeight,
                                 Math.max(240, (dialog.parent ? dialog.parent.height : 720) - 160))
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            id: column
            width: scroll.availableWidth
            spacing: 6

            Label {
                objectName: "activityEmpty"
                visible: dialog.days.length === 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                text: qsTr("No agent activity yet. Changes agents make to the board will be listed here.")
            }

            Repeater {
                model: dialog.days
                delegate: ColumnLayout {
                    id: day
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        objectName: "daySummary"
                        Layout.fillWidth: true
                        Layout.topMargin: day.index > 0 ? 12 : 0
                        wrapMode: Text.Wrap
                        font.bold: true
                        text: day.modelData.summary
                    }
                    Repeater {
                        model: day.modelData.entries
                        delegate: RowLayout {
                            id: row
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10
                            Label {
                                color: Theme.subtleText
                                text: row.modelData.time
                            }
                            Label {
                                objectName: "activityEntry"
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: row.modelData.text
                            }
                        }
                    }
                }
            }
        }
    }
}
