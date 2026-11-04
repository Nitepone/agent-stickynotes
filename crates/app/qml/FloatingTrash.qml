import QtQuick
import StickyNotes

// The trash can for when the bottom bar is hidden: it shows only while a task
// is being dragged (never while editing columns) and is gone again when the
// drag ends or is cancelled. The owner anchors it to a corner of the board.
Item {
    id: root

    property bool barShown: true
    property bool dragging: false
    property bool editMode: false

    signal taskDropped(string taskId)

    visible: !barShown && dragging && !editMode
    width: can.implicitWidth
    height: can.implicitHeight

    TrashCan {
        id: can
        objectName: "floatingTrashCan"
        anchors.fill: parent
        dragInProgress: true
        onTaskDropped: (taskId) => root.taskDropped(taskId)
    }
}
