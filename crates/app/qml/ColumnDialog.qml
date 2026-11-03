import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// View or edit a column's title and the meaning of its stage.
StickyDialog {
    id: dialog

    property string columnId: ""        // empty when creating
    property int position: -1
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
    maxWidth: Theme.px(520)
    acceptEnabled: titleField.text.trim().length > 0
    onAcceptClicked: saveRequested(columnId, position, titleField.text, descriptionField.text)

    contentItem: ColumnLayout {
        spacing: Theme.px(6)

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
            font.pixelSize: Theme.fs(12)
        }
        FormTextArea {
            id: descriptionField
            Layout.fillWidth: true
            Layout.minimumHeight: Theme.px(120)
            placeholderText: qsTr("e.g. Implementation is complete and all acceptance criteria are checked off.")
        }

        ErrorLabel { text: dialog.errorText }
    }
}
