import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Preferences: a sidebar of sections with the selected section's page beside
// it. Sections are the page's children, so adding one is just another element:
//
//     PreferencesPage {
//         PersonalizationSection { }
//         SomethingElseSection { }     // appears in the sidebar by its title
//     }
//
// The first section is shown when the page is created.
Item {
    id: root

    default property alias sections: stack.data
    property alias currentIndex: sidebar.currentIndex
    readonly property int sectionCount: stack.children.length

    signal backRequested()

    // Move keyboard focus to the sidebar (call when the page is shown).
    function focusSidebar() {
        sidebar.forceActiveFocus()
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

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.preferredWidth: Theme.px(230)
            Layout.fillHeight: true
            color: Theme.surface

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(12)
                spacing: Theme.px(12)

                Button {
                    objectName: "backButton"
                    Layout.fillWidth: true
                    text: qsTr("←  Back to board")
                    onClicked: root.backRequested()
                }

                Label {
                    text: qsTr("Preferences")
                    font.pixelSize: Theme.fs(18)
                    font.bold: true
                    color: Theme.text
                }

                ListView {
                    id: sidebar
                    objectName: "sidebar"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: stack.children.length
                    currentIndex: 0
                    clip: true
                    focus: true
                    activeFocusOnTab: true
                    keyNavigationEnabled: true
                    keyNavigationWraps: false
                    spacing: Theme.px(2)

                    delegate: ItemDelegate {
                        id: entry
                        required property int index
                        objectName: "sidebarItem" + index
                        width: ListView.view.width
                        text: stack.children[index].title
                        highlighted: ListView.isCurrentItem
                        onClicked: {
                            sidebar.currentIndex = index
                            sidebar.forceActiveFocus()
                        }

                        background: Rectangle {
                            radius: Theme.px(6)
                            color: entry.highlighted ? Theme.primary
                                   : entry.hovered ? Theme.controlHover : "transparent"
                            border.width: sidebar.activeFocus && entry.highlighted ? 2 : 0
                            border.color: Theme.text
                        }
                        contentItem: Label {
                            text: entry.text
                            font.bold: entry.highlighted
                            color: entry.highlighted ? Theme.textOnPrimary : Theme.text
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: sidebar.currentIndex
        }
    }
}
