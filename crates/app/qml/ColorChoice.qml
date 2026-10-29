import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import StickyNotes

// Choose an accent color: preset swatches, a hex field, or the system color
// picker. Emits `chosen("#rrggbb")`; the owner decides what to do with it.
ColumnLayout {
    id: choice

    property string label: ""
    property string description: ""
    // True when the user has not picked a color and the theme's default shows.
    property bool isDefault: true
    // Swatches offered.
    property var presets: Theme.accentPresets
    // The color currently in use (custom or default).
    property color effective: "transparent"

    signal chosen(string color)

    spacing: 6

    function apply(text) {
        const value = text.trim()
        if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(value)) {
            hexField.invalid = false
            if (!Theme.sameColor(value, effective))
                chosen(value)
        } else {
            hexField.invalid = true
        }
    }

    onEffectiveChanged: hexField.text = effective.toString()

    Label {
        text: choice.label
        font.bold: true
        color: Theme.text
    }
    Label {
        Layout.fillWidth: true
        text: choice.description
        wrapMode: Text.Wrap
        color: Theme.subtleText
        font.pixelSize: 12
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: choice.presets
            delegate: Rectangle {
                id: swatch
                required property string modelData
                readonly property bool selected: Theme.sameColor(modelData, choice.effective)

                objectName: "swatch-" + modelData
                width: 30
                height: 30
                radius: 15
                color: modelData
                border.width: selected ? 3 : 1
                border.color: selected ? Theme.text : Theme.fieldBorder

                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData
                Accessible.checked: selected

                Label {
                    anchors.centerIn: parent
                    visible: swatch.selected
                    text: "✓"
                    font.bold: true
                    color: Theme.readableOn(swatch.modelData)
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: choice.chosen(swatch.modelData)
                }
            }
        }
    }

    RowLayout {
        spacing: 8

        TextField {
            id: hexField
            objectName: "hexField"
            property bool invalid: false
            Layout.preferredWidth: 120
            text: choice.effective.toString()
            placeholderText: "#rrggbb"
            maximumLength: 7
            selectByMouse: true
            onEditingFinished: choice.apply(text)
            onTextEdited: invalid = false
            background: Rectangle {
                radius: 3
                color: Theme.fieldBackground
                border.color: hexField.invalid ? Theme.danger
                              : hexField.activeFocus ? Theme.primary : Theme.fieldBorder
            }
        }
        Button {
            objectName: "pickButton"
            text: qsTr("Pick…")
            onClicked: {
                picker.selectedColor = choice.effective
                picker.open()
            }
        }
        Label {
            visible: choice.isDefault
            text: qsTr("Default")
            color: Theme.subtleText
        }
        Label {
            objectName: "hexError"
            visible: hexField.invalid
            text: qsTr("Use a color like #2563eb")
            color: Theme.danger
        }
    }

    ColorDialog {
        id: picker
        title: choice.label
        onAccepted: choice.chosen(selectedColor.toString())
    }
}
