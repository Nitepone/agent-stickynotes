import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StickyNotes

// View or edit a column's title and the meaning of its stage.
Dialog {
    id: dialog

    property string columnId: ""        // empty when creating
    property int position: -1
    property string errorText: ""
    readonly property bool creating: columnId === ""

    signal saveRequested(string columnId, int position, string title, string description)

    function openColumn(column) {
        columnId = column.id
        position = -1
        titleField.text = column.title
        descriptionField.text = column.description
        errorText = ""
        open()
    }

    function openNew(atPosition) {
        columnId = ""
        position = atPosition
        titleField.text = ""
        descriptionField.text = ""
        errorText = ""
        open()
        titleField.forceActiveFocus()
    }

    title: creating ? qsTr("New column") : qsTr("Column")
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(520, (parent ? parent.width : 520) - 40)
    padding: 16

    contentItem: ColumnLayout {
        spacing: 6

        SectionLabel { text: qsTr("Title *"); Layout.topMargin: 0 }
        TextField {
            id: titleField
            Layout.fillWidth: true
            placeholderText: qsTr("e.g. In Review")
        }

        SectionLabel { text: qsTr("What this stage means") }
        Label {
            Layout.fillWidth: true
            text: qsTr("Describe what must be true for a task to be in this column. Agents check this before advancing a task here.")
            wrapMode: Text.Wrap
            color: Theme.subtleText
            font.pixelSize: 12
        }
        FormTextArea {
            id: descriptionField
            Layout.fillWidth: true
            Layout.minimumHeight: 120
            placeholderText: qsTr("e.g. Implementation is complete and all acceptance criteria are checked off.")
        }

        Label {
            Layout.fillWidth: true
            visible: dialog.errorText !== ""
            text: dialog.errorText
            color: Theme.danger
            wrapMode: Text.Wrap
        }
    }

    footer: DialogButtonBox {
        Button {
            text: qsTr("Cancel")
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Button {
            text: qsTr("Save")
            highlighted: true
            enabled: titleField.text.trim().length > 0
            DialogButtonBox.buttonRole: DialogButtonBox.ApplyRole
            onClicked: dialog.saveRequested(dialog.columnId, dialog.position, titleField.text, descriptionField.text)
        }
    }
}
