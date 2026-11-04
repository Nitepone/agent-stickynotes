import QtQuick
import QtQuick.Controls.Fusion
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
    property string noteColor: ""           // custom note color, or "" for the yellow
    property string noteStyle: "user"       // "user" or "variable" (a palette color per category)
    property string notePalette: ""         // palette id for "variable"; "" is the first
    property string motionSetting: "system"     // "system", "on" or "off"
    property bool showBottomBar: true

    signal themeModeChosen(string mode)
    signal primaryColorChosen(string color)
    signal secondaryColorChosen(string color)
    signal resetColorsRequested()
    signal noteColorChosen(string color)
    signal resetNoteColorRequested()
    signal noteStyleChosen(string style)
    signal notePaletteChosen(string id)
    signal motionSettingChosen(string setting)
    signal showBottomBarChosen(bool shown)

    ScrollView {
        id: scroll
        objectName: "personalizationScroll"
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            x: Theme.px(32)
            y: Theme.px(24)
            width: Math.min(scroll.availableWidth - Theme.px(64), Theme.px(640))
            spacing: Theme.px(14)

            Label {
                text: qsTr("Color theme")
                font.pixelSize: Theme.fs(22)
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
                spacing: Theme.px(12)

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
                        implicitWidth: Theme.px(150)
                        implicitHeight: Theme.px(64)
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
                            font.pixelSize: Theme.fs(16)
                            font.bold: option.selected
                            color: Theme.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Label {
                Layout.topMargin: Theme.px(12)
                text: qsTr("Accent colors")
                font.pixelSize: Theme.fs(22)
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

            Label {
                Layout.topMargin: Theme.px(12)
                text: qsTr("Sticky notes")
                font.pixelSize: Theme.fs(22)
                font.bold: true
                color: Theme.text
            }

            Label {
                text: qsTr("Note style")
                font.bold: true
                color: Theme.text
            }
            ComboBox {
                id: styleBox
                objectName: "noteStyleBox"
                Layout.preferredWidth: Theme.px(260)
                textRole: "label"
                valueRole: "value"
                model: [
                    { value: "user", label: qsTr("User color") },
                    { value: "variable", label: qsTr("Variable") }
                ]
                onActivated: section.noteStyleChosen(currentValue)
                Accessible.name: qsTr("Note style")

                // Shows the stored style, and keeps doing so after the user
                // has picked something (a plain binding would be dropped).
                Binding {
                    target: styleBox
                    property: "currentIndex"
                    value: styleBox.count >= 0 ? Math.max(0, styleBox.indexOfValue(section.noteStyle)) : 0
                }
            }
            Label {
                Layout.fillWidth: true
                text: section.noteStyle === "variable"
                      ? qsTr("Notes get a color from the palette according to their category. Text on a note adjusts to stay readable.")
                      : qsTr("All notes use the one color you choose.")
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: Theme.fs(12)
            }

            // Style "User color": the single note color.
            ColumnLayout {
                objectName: "userNoteControls"
                Layout.fillWidth: true
                visible: section.noteStyle !== "variable"
                spacing: Theme.px(14)

                ColorChoice {
                    objectName: "noteChoice"
                    Layout.fillWidth: true
                    label: qsTr("Note color")
                    description: qsTr("The color of the notes on the board. Text on a note adjusts to stay readable.")
                    presets: Theme.notePresets
                    isDefault: section.noteColor === ""
                    effective: Theme.note
                    onChosen: (color) => section.noteColorChosen(color)
                }

                Button {
                    objectName: "resetNoteColor"
                    text: qsTr("Reset note color")
                    enabled: section.noteColor !== ""
                    onClicked: section.resetNoteColorRequested()
                }
            }

            // Style "Variable": the palettes to choose from.
            NotePaletteChoice {
                objectName: "paletteChoice"
                Layout.fillWidth: true
                visible: section.noteStyle === "variable"
                selectedId: section.notePalette
                onChosen: (id) => section.notePaletteChosen(id)
            }

            Label {
                Layout.topMargin: Theme.px(12)
                text: qsTr("Motion")
                font.pixelSize: Theme.fs(22)
                font.bold: true
                color: Theme.text
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("Notes an agent changed glow, with a moving highlight and a sheen. With reduced motion they show a still glow instead.")
                wrapMode: Text.Wrap
                color: Theme.subtleText
            }
            ComboBox {
                id: motionBox
                objectName: "motionBox"
                Layout.preferredWidth: Theme.px(260)
                textRole: "label"
                valueRole: "value"
                model: [
                    { value: "system", label: qsTr("Follow the system setting") },
                    { value: "on", label: qsTr("Reduce motion") },
                    { value: "off", label: qsTr("Allow motion") }
                ]
                onActivated: section.motionSettingChosen(currentValue)

                // Shows the stored setting, and keeps doing so after the user
                // has picked something (a plain binding would be dropped).
                Binding {
                    target: motionBox
                    property: "currentIndex"
                    value: motionBox.count >= 0 ? Math.max(0, motionBox.indexOfValue(section.motionSetting)) : 0
                }
            }

            Label {
                Layout.topMargin: Theme.px(12)
                text: qsTr("Layout")
                font.pixelSize: Theme.fs(22)
                font.bold: true
                color: Theme.text
            }
            CheckBox {
                id: barBox
                objectName: "showBottomBarBox"
                text: qsTr("Show bottom bar")
                checked: section.showBottomBar
                onToggled: {
                    section.showBottomBarChosen(checked)
                    checked = Qt.binding(() => section.showBottomBar)
                }
                Accessible.name: qsTr("Show bottom bar")
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("The bar at the bottom shows a hint and the trash can. When hidden, the trash can appears over the board while you drag a task.")
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: Theme.fs(12)
            }
        }
    }
}
