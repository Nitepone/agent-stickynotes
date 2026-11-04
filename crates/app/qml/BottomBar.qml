import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// The strip at the bottom of the window: a hint and the trash can. The owner
// decides when it shows (it is the window's footer, so hiding it gives the
// board the height back).
ToolBar {
    id: bar

    property bool dragging: false
    property bool editMode: false

    signal taskDropped(string taskId)

    implicitHeight: Theme.px(60)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.px(16)
        anchors.rightMargin: Theme.px(16)

        Label {
            objectName: "barHint"
            Layout.fillWidth: true
            elide: Text.ElideMiddle
            color: bar.dragging ? Theme.text : Theme.subtleText
            text: bar.dragging && !bar.editMode
                  ? qsTr("Drop on a column to move the task, or on the trash can to delete it.")
                  : bar.editMode
                    ? qsTr("Editing columns: drag ☰ to reorder, ✕ to delete.")
                    : qsTr("Click a task or column title to edit it. Drag tasks between columns.")
        }

        TrashCan {
            objectName: "barTrash"
            Layout.alignment: Qt.AlignVCenter
            visible: !bar.editMode
            dragInProgress: bar.dragging
            onTaskDropped: (taskId) => bar.taskDropped(taskId)
        }
    }
}
