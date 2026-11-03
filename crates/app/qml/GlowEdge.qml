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
        model: [ { grow: 0, alpha: 0.95 }, { grow: 2 * Theme.scale, alpha: 0.45 }, { grow: 4 * Theme.scale, alpha: 0.2 } ]
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
    // It is a trail of small dots, each placed on the outline separately, so
    // the trail bends round the corners instead of sticking out of them.
    property real cometProgress: 0      // 0 to 1: where the head is along the outline
    readonly property int cometPieces: 14
    readonly property real cometLength: 48 * Theme.scale          // arc length of the whole trail
    readonly property real outlineLength: Math.max(1,
        2 * Math.max(0, width - 2 * cornerRadius) + 2 * Math.max(0, height - 2 * cornerRadius)
        + 2 * Math.PI * cornerRadius)

    // The point at `p` (0 to 1) along the note's rounded outline, clockwise
    // from the end of the top-left corner. The one definition of the path.
    function outlinePoint(p) {
        const r = Math.min(cornerRadius, width / 2, height / 2)
        const sw = Math.max(0, width - 2 * r)
        const sh = Math.max(0, height - 2 * r)
        const arc = Math.PI * r / 2
        const segments = [sw, arc, sh, arc, sw, arc, sh, arc]
        let d = (((p % 1) + 1) % 1) * (2 * sw + 2 * sh + 4 * arc)
        let i = 0
        while (i < 7 && d > segments[i]) {
            d -= segments[i]
            i++
        }
        const t = Math.min(1, segments[i] > 0 ? d / segments[i] : 0)
        const a = t * Math.PI / 2
        switch (i) {
        case 0: return Qt.point(r + d, 0)
        case 1: return Qt.point(width - r + r * Math.sin(a), r - r * Math.cos(a))
        case 2: return Qt.point(width, r + d)
        case 3: return Qt.point(width - r + r * Math.cos(a), height - r + r * Math.sin(a))
        case 4: return Qt.point(width - r - d, height)
        case 5: return Qt.point(r - r * Math.sin(a), height - r + r * Math.cos(a))
        case 6: return Qt.point(0, height - r - d)
        default: return Qt.point(r - r * Math.cos(a), r - r * Math.sin(a))
        }
    }

    Item {
        id: comet
        objectName: "comet"
        visible: root.animated

        Repeater {
            model: root.cometPieces
            delegate: Rectangle {
                required property int index
                readonly property real fade: index / (root.cometPieces - 1)     // 0 at the head, 1 at the tail
                readonly property point spot: root.outlinePoint(root.cometProgress
                    - index * root.cometLength / (root.cometPieces - 1) / root.outlineLength)
                objectName: "cometPiece"
                width: (7 - 4.5 * fade) * Theme.scale
                height: width
                radius: width / 2
                x: spot.x - width / 2
                y: spot.y - height / 2
                color: Theme.glowCore
                opacity: 1 - fade
            }
        }
    }

    NumberAnimation {
        id: cometAnimation
        objectName: "cometAnimation"
        target: root
        property: "cometProgress"
        from: 0
        to: 1
        running: root.animated
        loops: Animation.Infinite
        duration: Theme.glowRotationMs
    }

    // The sheen: a slanted translucent band moving left to right, then a pause.
    Item {
        anchors.fill: parent
        clip: true
        visible: root.edited && root.animated

        Rectangle {
            id: sheen
            objectName: "sheen"
            width: Theme.px(36)
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
