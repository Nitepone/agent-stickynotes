import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// A dialog's error message; hidden while empty.
Label {
    Layout.fillWidth: true
    visible: text !== ""
    color: Theme.danger
    wrapMode: Text.Wrap
}
