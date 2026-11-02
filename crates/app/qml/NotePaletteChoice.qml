import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Choose the palette for notes that vary by category: one row per palette,
// its name and a strip of its colors in the order they are handed out.
// Emits `chosen(id)`; the owner stores it and feeds `selectedId` back.
ColumnLayout {
    id: choice

    property string selectedId: ""      // "" means the first palette

    readonly property string currentId: Theme.paletteById(selectedId).id

    signal chosen(string id)

    spacing: 6

    Label {
        text: qsTr("Note palette")
        font.bold: true
        color: Theme.text
    }
    Label {
        Layout.fillWidth: true
        text: qsTr("Each category gets the next color of the palette, in alphabetical order. Uncategorized notes keep your note color.")
        wrapMode: Text.Wrap
        color: Theme.subtleText
        font.pixelSize: 12
    }

    Repeater {
        model: Theme.notePalettes
        delegate: Button {
            id: row
            required property var modelData
            readonly property bool selected: choice.currentId === modelData.id

            objectName: "palette-" + modelData.id
            Layout.fillWidth: true
            implicitHeight: 44
            checkable: true
            checked: selected
            activeFocusOnTab: true
            // Checked state is driven by the setting, not by clicking.
            onClicked: {
                checked = Qt.binding(() => row.selected)
                choice.chosen(modelData.id)
            }

            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.name
            Accessible.description: qsTr("%1 colors").arg(modelData.colors.length)
            Accessible.checked: selected

            background: Rectangle {
                radius: Theme.radius
                color: row.selected ? Theme.columnBackground
                       : row.hovered ? Theme.controlHover : Theme.controlBackground
                border.width: row.selected ? 3 : 1
                border.color: row.selected ? Theme.primary : Theme.fieldBorder

                Rectangle {
                    objectName: "focusRing"
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: Theme.radius + 3
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.focusRing
                    visible: row.visualFocus
                }
            }

            contentItem: RowLayout {
                spacing: 12

                Label {
                    Layout.preferredWidth: 90
                    text: (row.selected ? "✓  " : "") + row.modelData.name
                    font.bold: row.selected
                    color: Theme.text
                }
                Repeater {
                    model: row.modelData.colors
                    delegate: Rectangle {
                        required property string modelData
                        objectName: "paletteColor"
                        implicitWidth: 18
                        implicitHeight: 18
                        radius: 9
                        color: modelData
                        border.width: 1
                        border.color: Theme.fieldBorder
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
