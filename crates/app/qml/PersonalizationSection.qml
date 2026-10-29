import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StickyNotes

// Preferences > Personalization: the color theme. Emits what the user picked;
// the owner applies and saves it, then feeds the new values back in.
PreferencesSection {
    id: section

    title: qsTr("Personalization")

    property string themeMode: "light"      // "light" or "dark"
    property string primaryColor: ""        // custom color, or "" for the default
    property string secondaryColor: ""

    signal themeModeChosen(string mode)
    signal primaryColorChosen(string color)
    signal secondaryColorChosen(string color)
    signal resetColorsRequested()

    ScrollView {
        id: scroll
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            x: 32
            y: 24
            width: Math.min(scroll.availableWidth - 64, 640)
            spacing: 14

            Label {
                text: qsTr("Color theme")
                font.pixelSize: 22
                font.bold: true
                color: Theme.text
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("Choose how the app looks. Changes apply right away and are remembered.")
                wrapMode: Text.Wrap
                color: Theme.subtleText
            }

            RowLayout {
                spacing: 12

                Repeater {
                    model: [
                        { value: "light", label: qsTr("Light") },
                        { value: "dark", label: qsTr("Dark") }
                    ]
                    delegate: Button {
                        id: option
                        required property var modelData
                        readonly property bool selected: section.themeMode === modelData.value

                        objectName: "mode-" + modelData.value
                        checkable: true
                        checked: selected
                        implicitWidth: 150
                        implicitHeight: 64
                        // Checked state is driven by the setting, not by clicking.
                        onClicked: {
                            checked = Qt.binding(() => option.selected)
                            section.themeModeChosen(modelData.value)
                        }

                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData.label
                        Accessible.checked: selected

                        background: Rectangle {
                            radius: Theme.radius
                            color: option.selected ? Theme.columnBackground : Theme.controlBackground
                            border.width: option.selected ? 3 : 1
                            border.color: option.selected ? Theme.primary : Theme.fieldBorder
                        }
                        contentItem: Label {
                            text: (option.selected ? "✓  " : "") + option.modelData.label
                            font.pixelSize: 16
                            font.bold: option.selected
                            color: Theme.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Label {
                Layout.topMargin: 12
                text: qsTr("Accent colors")
                font.pixelSize: 22
                font.bold: true
                color: Theme.text
            }

            ColorChoice {
                objectName: "primaryChoice"
                Layout.fillWidth: true
                label: qsTr("Primary color")
                description: qsTr("Buttons, progress bars, drop targets, focus and selection.")
                isDefault: section.primaryColor === ""
                effective: Theme.primary
                onChosen: (color) => section.primaryColorChosen(color)
            }

            ColorChoice {
                objectName: "secondaryChoice"
                Layout.fillWidth: true
                label: qsTr("Secondary color")
                description: qsTr("Links, column editing and the add-column tile.")
                isDefault: section.secondaryColor === ""
                effective: Theme.secondary
                onChosen: (color) => section.secondaryColorChosen(color)
            }

            Button {
                objectName: "resetColors"
                text: qsTr("Reset colors to default")
                enabled: section.primaryColor !== "" || section.secondaryColor !== ""
                onClicked: section.resetColorsRequested()
            }
        }
    }
}
