import QtQuick
import StickyNotes

// The glow around a note an agent changed: a soft green border, a highlight
// that circles the note, and (if the note's content was edited) a sheen that
// sweeps across it. Fill the note with it; it takes no input.
//
// With `reducedMotion` only the static border remains. Nothing animates while
// the glow is invisible, so idle notes cost nothing.
Item {
    id: root

    property real intensity: 0          // 0 to 1; scales the whole effect
    property bool edited: false         // adds the sheen
    property bool reducedMotion: false
    // False for a note scrolled out of sight: it keeps its static glow but
    // its animations pause, so a long column of glowing notes stays cheap.
    property bool active: true
    property real cornerRadius: 4

    readonly property bool animated: active && intensity > 0 && !reducedMotion

    visible: intensity > 0
    opacity: intensity
    enabled: false                      // never takes mouse or keyboard input

    // Static glow: three rings, fading outward.
    Repeater {
        model: [ { grow: 0, alpha: 0.95 }, { grow: 2, alpha: 0.45 }, { grow: 4, alpha: 0.2 } ]
        delegate: Rectangle {
            required property var modelData
            objectName: "glowRing"
            anchors.fill: parent
            anchors.margins: -modelData.grow
            radius: root.cornerRadius + modelData.grow
            color: "transparent"
            border.width: 2
            border.color: Theme.glow
            opacity: modelData.alpha
        }
    }

    // A highlight that travels once around the edge of the note per rotation.
    Item {
        id: comet
        objectName: "comet"
        visible: root.animated
        width: 48
        height: 5

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Theme.glowCore }
            }
        }
        Rectangle {
            width: 7
            height: 7
            radius: 3.5
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.glowCore
        }
    }

    PathAnimation {
        id: cometAnimation
        objectName: "cometAnimation"
        target: comet
        running: root.animated
        loops: Animation.Infinite
        duration: Theme.glowRotationMs
        orientation: PathAnimation.RightFirst
        anchorPoint: Qt.point(comet.width, comet.height / 2)       // the head leads

        path: Path {
            startX: root.cornerRadius
            startY: 0
            PathLine { x: root.width - root.cornerRadius; y: 0 }
            PathArc { x: root.width; y: root.cornerRadius; radiusX: root.cornerRadius; radiusY: root.cornerRadius }
            PathLine { x: root.width; y: root.height - root.cornerRadius }
            PathArc { x: root.width - root.cornerRadius; y: root.height; radiusX: root.cornerRadius; radiusY: root.cornerRadius }
            PathLine { x: root.cornerRadius; y: root.height }
            PathArc { x: 0; y: root.height - root.cornerRadius; radiusX: root.cornerRadius; radiusY: root.cornerRadius }
            PathLine { x: 0; y: root.cornerRadius }
            PathArc { x: root.cornerRadius; y: 0; radiusX: root.cornerRadius; radiusY: root.cornerRadius }
        }
    }

    // The sheen: a slanted translucent band moving left to right, then a pause.
    Item {
        anchors.fill: parent
        clip: true
        visible: root.edited && root.animated

        Rectangle {
            id: sheen
            objectName: "sheen"
            width: 36
            height: parent.height * 1.8
            y: -parent.height * 0.4
            x: -width
            rotation: 20
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Theme.sheen }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        SequentialAnimation {
            id: sheenAnimation
            objectName: "sheenAnimation"
            running: root.edited && root.animated
            loops: Animation.Infinite
            NumberAnimation {
                objectName: "sheenSweep"
                target: sheen
                property: "x"
                from: -sheen.width
                to: root.width + sheen.width
                duration: Theme.glowSheenMs
                easing.type: Easing.InOutSine
            }
            PauseAnimation { duration: 900 }
        }
    }
}
