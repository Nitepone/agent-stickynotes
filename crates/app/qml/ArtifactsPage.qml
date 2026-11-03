import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Every file in the project's artifacts folder, newest first, under dividers
// for Today, This week, This month and Earlier. Each row has an icon (a
// picture or a document), the name, a pill for each task the file is
// attached to, and the date. Clicking the row opens the file; clicking a pill
// opens the task. `artifacts` is `BoardController.artifactsJson` parsed.
Item {
    id: root

    property var artifacts: []
    property real now: Date.now()          // tests set this to a fixed time

    signal backRequested()
    signal artifactClicked(string name)
    signal taskClicked(string taskId)

    readonly property int maxPills: 4
    readonly property var entries: build(artifacts, now)

    // The time bands, newest first. `days` counts back from the start of today.
    readonly property var bands: [
        { label: qsTr("Today"), days: 0 },
        { label: qsTr("This week"), days: 6 },
        { label: qsTr("This month"), days: 29 },
        { label: qsTr("Earlier"), days: -1 },
    ]

    function startOfDay(ms, daysBack) {
        const d = new Date(ms)
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() - daysBack).getTime()
    }

    // The flat list the view shows: `{header: "Today"}` dividers (only for
    // bands that have files) followed by `{file: <artifact>}` rows.
    function build(list, nowMs) {
        const sorted = list.slice().sort((a, b) => b.at - a.at)
        const out = []
        let band = -1
        for (const file of sorted) {
            let b = 0
            while (b < bands.length - 1 && file.at < startOfDay(nowMs, bands[b].days)) b++
            if (b !== band) {
                band = b
                out.push({ header: bands[b].label, file: null })
            }
            out.push({ header: "", file: file })
        }
        return out
    }

    function dateText(ms, nowMs) {
        const d = new Date(ms)
        return ms >= startOfDay(nowMs, 0) ? Qt.formatTime(d, Locale.ShortFormat)
                                          : Qt.formatDate(d, Locale.ShortFormat)
    }

    Keys.onEscapePressed: root.backRequested()

    Rectangle {
        anchors.fill: parent
        color: Theme.background

        // Nothing underneath (the board) may receive clicks or scrolling.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onWheel: (wheel) => wheel.accepted = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(16)
        spacing: Theme.px(12)

        RowLayout {
            spacing: Theme.px(12)
            Button {
                objectName: "backButton"
                text: qsTr("← Back to board")
                onClicked: root.backRequested()
            }
            Label {
                objectName: "artifactsTitle"
                text: qsTr("Artifacts")
                font.pixelSize: Theme.fs(20)
                font.bold: true
                color: Theme.text
            }
            Label {
                objectName: "artifactCount"
                visible: root.artifacts.length > 0
                color: Theme.subtleText
                text: root.artifacts.length === 1 ? qsTr("1 file")
                                                  : qsTr("%1 files").arg(root.artifacts.length)
            }
        }

        Label {
            objectName: "artifactsEmpty"
            visible: root.artifacts.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true      // keeps the header pinned to the top
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            color: Theme.subtleText
            text: qsTr("No files in this project's artifacts folder yet. Agents attach them to tasks.")
        }

        ListView {
            id: list
            objectName: "artifactList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.artifacts.length > 0
            clip: true
            spacing: Theme.px(6)
            model: root.entries
            ScrollBar.vertical: ScrollBar {}

            delegate: Item {
                id: entry
                required property var modelData
                readonly property bool isHeader: modelData.header !== ""
                readonly property var file: modelData.file

                width: list.width - Theme.px(12)
                height: isHeader ? Theme.px(30) : Theme.px(48)

                // Divider
                RowLayout {
                    visible: entry.isHeader
                    anchors.fill: parent
                    anchors.topMargin: Theme.px(6)
                    spacing: Theme.px(10)
                    Label {
                        objectName: "sectionHeader"
                        text: entry.modelData.header
                        font.bold: true
                        color: Theme.subtleText
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Theme.fieldBorder
                    }
                }

                // File row
                Rectangle {
                    visible: !entry.isHeader
                    anchors.fill: parent
                    radius: Theme.px(6)
                    color: open.containsMouse ? Theme.controlHover : Theme.controlBackground

                    MouseArea {
                        id: open
                        objectName: "artifactRow"
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.artifactClicked(entry.file.name)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(12)
                        anchors.rightMargin: Theme.px(12)
                        spacing: Theme.px(10)

                        ToolIcon {
                            objectName: "artifactIcon"
                            implicitWidth: Theme.px(24)
                            implicitHeight: Theme.px(24)
                            kind: entry.file && entry.file.kind === "image" ? "image" : "document"
                            color: Theme.text
                        }
                        Label {
                            objectName: "artifactName"
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            elide: Text.ElideRight
                            text: entry.file ? entry.file.name : ""
                            color: Theme.text
                        }

                        Label {
                            objectName: "notAttached"
                            visible: entry.file !== null && entry.file.tasks.length === 0
                            text: qsTr("not attached")
                            color: Theme.subtleText
                            font.pixelSize: Theme.fs(12)
                        }
                        Repeater {
                            model: entry.file ? entry.file.tasks.slice(0, root.maxPills) : []
                            delegate: Rectangle {
                                id: pill
                                required property var modelData
                                objectName: "artifactPill"
                                implicitWidth: pillText.implicitWidth + Theme.px(16)
                                implicitHeight: Theme.px(22)
                                radius: Theme.px(11)
                                color: Theme.secondary
                                border.width: pillArea.containsMouse ? 2 : 0
                                border.color: Theme.text
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Task #%1").arg(modelData.number)

                                Label {
                                    id: pillText
                                    anchors.centerIn: parent
                                    text: "#" + pill.modelData.number
                                    color: Theme.textOnSecondary
                                    font.pixelSize: Theme.fs(12)
                                    font.bold: true
                                }
                                MouseArea {
                                    id: pillArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.taskClicked(pill.modelData.id)
                                }
                            }
                        }
                        Label {
                            objectName: "morePills"
                            visible: entry.file !== null && entry.file.tasks.length > root.maxPills
                            text: entry.file ? "+" + (entry.file.tasks.length - root.maxPills) : ""
                            color: Theme.subtleText
                            font.pixelSize: Theme.fs(12)
                        }

                        Label {
                            objectName: "artifactDate"
                            Layout.preferredWidth: Theme.px(90)
                            horizontalAlignment: Text.AlignRight
                            text: entry.file ? root.dateText(entry.file.at, root.now) : ""
                            color: Theme.subtleText
                            font.pixelSize: Theme.fs(12)
                        }
                    }
                }
            }
        }
    }
}
