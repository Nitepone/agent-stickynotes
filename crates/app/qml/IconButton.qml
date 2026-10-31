import QtQuick
import QtQuick.Controls.Fusion
import StickyNotes

// A toolbar button that shows an icon (see ToolIcon for the kinds). `tip` is
// its tooltip and its accessible name. Checkable buttons show as pressed in
// the primary color. A `badge` button is filled with `badgeColor`, which is
// how the agent button shows its state.
ToolButton {
    id: button

    property string glyph: ""
    property string tip: ""
    property bool badge: false
    property color badgeColor: Theme.primary
    property color badgeGlyphColor: Theme.textOnPrimary

    readonly property color glyphColor: badge ? badgeGlyphColor
                                        : checked ? Theme.textOnPrimary : Theme.text

    implicitWidth: 36
    implicitHeight: 32
    focusPolicy: Qt.StrongFocus

    Accessible.name: tip
    ToolTip.visible: hovered && tip !== ""
    ToolTip.delay: 600
    ToolTip.text: tip

    background: Rectangle {
        radius: 4
        color: button.badge ? button.badgeColor
               : button.checked ? Theme.primary
               : button.down ? Theme.controlDown
               : button.hovered ? Theme.controlHover : "transparent"
        border.width: button.badge && (button.hovered || button.visualFocus) ? 2 : 0
        border.color: Theme.text
    }

    contentItem: Item {
        ToolIcon {
            anchors.centerIn: parent
            kind: button.glyph
            color: button.glyphColor
        }
    }
}
