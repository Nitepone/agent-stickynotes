import QtQuick
import StickyNotes

// A small line icon drawn in code, so it takes its color from the theme and
// needs no image files. `kind` is one of "save" (floppy disk), "gear",
// "pencil", "robot", "folder", "document" or "image"; add another by adding a case to `draw`.
Canvas {
    id: icon

    property string kind: ""
    property color color: Theme.text
    property real strokeWidth: 1.8      // in the 24 x 24 drawing grid

    implicitWidth: Theme.px(22)
    implicitHeight: Theme.px(22)

    onKindChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function polygon(ctx, points) {
        ctx.beginPath()
        ctx.moveTo(points[0][0], points[0][1])
        for (let i = 1; i < points.length; i++)
            ctx.lineTo(points[i][0], points[i][1])
        ctx.closePath()
        ctx.stroke()
    }

    function line(ctx, x1, y1, x2, y2) {
        ctx.beginPath()
        ctx.moveTo(x1, y1)
        ctx.lineTo(x2, y2)
        ctx.stroke()
    }

    function circle(ctx, x, y, r, filled) {
        ctx.beginPath()
        ctx.arc(x, y, r, 0, 2 * Math.PI)
        if (filled) ctx.fill()
        else ctx.stroke()
    }

    // The outline of a gear: eight teeth around (12, 12).
    function gearPoints() {
        const points = []
        const at = (degrees, radius) => {
            const a = degrees * Math.PI / 180
            return [12 + radius * Math.cos(a), 12 + radius * Math.sin(a)]
        }
        for (let i = 0; i < 8; i++) {
            const a = i * 45
            points.push(at(a - 9, 10), at(a + 9, 10), at(a + 15, 7.4), at(a + 30, 7.4))
        }
        return points
    }

    function draw(ctx) {
        switch (kind) {
        case "save":        // floppy disk: body with a cut corner, shutter, label
            polygon(ctx, [[3, 3], [17, 3], [21, 7], [21, 21], [3, 21]])
            polygon(ctx, [[7, 3], [7, 8], [15, 8], [15, 3]])
            polygon(ctx, [[6, 21], [6, 13], [18, 13], [18, 21]])
            break
        case "gear":
            polygon(ctx, gearPoints())
            circle(ctx, 12, 12, 3, false)
            break
        case "pencil":      // a pencil lying diagonally, tip at the lower left
            polygon(ctx, [[16, 3], [21, 8], [8, 21], [3, 21], [3, 16]])
            line(ctx, 13, 6, 18, 11)
            break
        case "folder":
            polygon(ctx, [[3, 6], [9, 6], [11, 8], [21, 8], [21, 19], [3, 19]])
            break
        case "document":    // a page with a folded corner and two lines of text
            polygon(ctx, [[6, 3], [14, 3], [19, 8], [19, 21], [6, 21]])
            line(ctx, 14, 3, 14, 8)
            line(ctx, 14, 8, 19, 8)
            line(ctx, 9, 13, 16, 13)
            line(ctx, 9, 17, 16, 17)
            break
        case "image":       // a framed picture: a sun and two hills
            polygon(ctx, [[3, 5], [21, 5], [21, 19], [3, 19]])
            circle(ctx, 8.5, 10, 1.8, false)
            ctx.beginPath()
            ctx.moveTo(3, 17)
            ctx.lineTo(9, 12)
            ctx.lineTo(13, 16)
            ctx.lineTo(16, 13)
            ctx.lineTo(21, 17.5)
            ctx.stroke()
            break
        case "robot":       // a head with an antenna, ears, eyes and a mouth
            polygon(ctx, [[5, 8], [19, 8], [19, 20], [5, 20]])
            line(ctx, 12, 8, 12, 4.5)
            circle(ctx, 12, 3.3, 1.2, true)
            line(ctx, 3, 12, 3, 16)
            line(ctx, 21, 12, 21, 16)
            circle(ctx, 9, 13, 1.5, true)
            circle(ctx, 15, 13, 1.5, true)
            line(ctx, 9.5, 17, 14.5, 17)
            break
        }
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.scale(width / 24, height / 24)
        ctx.strokeStyle = color.toString()
        ctx.fillStyle = color.toString()
        ctx.lineWidth = strokeWidth
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        draw(ctx)
    }
}
