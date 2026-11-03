import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Toolbar controls for the board's view-only filter: a text box, a category
// picker and the "hide old tasks in the last column" option. They edit a
// TaskFilter; they never touch the board.
RowLayout {
    id: root

    required property var filter          // TaskFilter
    property var categories: []           // categories in use on the board
    property string lastColumnTitle: ""

    spacing: Theme.px(4)

    function focusField() {
        field.forceActiveFocus()
        field.selectAll()
    }

    TextField {
        id: field
        objectName: "filterField"
        Layout.preferredWidth: Theme.px(200)
        placeholderText: qsTr("Filter (Ctrl+F)")
        text: root.filter.text
        onTextEdited: root.filter.text = text
        Accessible.name: qsTr("Filter tasks by text or number")
        Keys.onEscapePressed: (event) => {
            if (root.filter.active) {
                root.filter.clear()
                event.accepted = true
            } else {
                event.accepted = false
            }
        }
    }

    ToolButton {
        objectName: "clearFilterButton"
        visible: root.filter.active
        text: "✕"
        implicitWidth: Theme.px(28)
        implicitHeight: Theme.px(28)
        Accessible.name: qsTr("Clear the filter")
        onClicked: root.filter.clear()
        ToolTip.visible: hovered
        ToolTip.text: qsTr("Clear the filter")
        ToolTip.delay: 600
    }

    Button {
        id: options
        objectName: "filterOptionsButton"
        text: root.filter.categories.length > 0 || root.filter.hideOldDone
              ? qsTr("Filters (%1)").arg(root.filter.categories.length + (root.filter.hideOldDone ? 1 : 0))
              : qsTr("Filters")
        flat: true
        Accessible.name: qsTr("Category and age filters")
        onClicked: popup.opened ? popup.close() : popup.open()
    }

    Popup {
        id: popup
        parent: options
        y: options.height
        padding: Theme.px(12)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        ColumnLayout {
            spacing: Theme.px(6)

            Label {
                text: qsTr("Categories")
                font.bold: true
                color: Theme.text
            }
            Label {
                visible: root.categories.length === 0
                text: qsTr("No categories in use.")
                color: Theme.subtleText
            }
            Repeater {
                model: root.categories
                delegate: CheckBox {
                    required property string modelData
                    text: modelData
                    checked: root.filter.hasCategory(modelData)
                    onToggled: root.filter.toggleCategory(modelData)
                    Accessible.name: qsTr("Show category %1").arg(modelData)
                }
            }

            Label {
                Layout.topMargin: Theme.px(6)
                text: qsTr("Age")
                font.bold: true
                color: Theme.text
            }
            CheckBox {
                text: qsTr("Hide %1 tasks not changed for").arg(root.lastColumnTitle)
                checked: root.filter.hideOldDone
                onToggled: root.filter.hideOldDone = checked
                Accessible.name: qsTr("Hide %1 tasks not changed for the chosen number of days").arg(root.lastColumnTitle)
            }
            ComboBox {
                Layout.leftMargin: Theme.px(28)
                model: [7, 30, 90]
                displayText: qsTr("%n day(s)", "", currentValue)
                currentIndex: Math.max(0, model.indexOf(root.filter.days))
                onActivated: root.filter.days = model[currentIndex]
                Accessible.name: qsTr("Number of days")
            }
        }
    }
}
