import QtQuick
import QtQuick.Controls
import QtTest
import StickyNotes

Item {
    id: scene
    width: 400
    height: 200

    Row {
        spacing: 10
        ToolIcon { id: floppy; objectName: "floppy"; kind: "save"; width: 48; height: 48; color: "black" }
        IconButton { id: plain; objectName: "plain"; glyph: "gear"; tip: "Preferences" }
        IconButton { id: toggle; objectName: "toggle"; glyph: "pencil"; tip: "Edit columns"; checkable: true }
        IconButton {
            id: agent
            objectName: "agent"
            glyph: "robot"
            tip: "Agent"
            badge: true
            badgeColor: Theme.agentReadOnly
            badgeGlyphColor: Theme.textOnAgentReadOnly
        }
    }

    SignalSpy { id: clickSpy; target: plain; signalName: "clicked" }

    TestCase {
        name: "IconButton"
        when: windowShown

        function init() {
            clickSpy.clear()
            toggle.checked = false
            Theme.mode = "light"
        }

        // How many pixels of the item differ from its empty corner, and the strongest of them.
        function inked(item) {
            const image = grabImage(item)
            const bg = Qt.color(image.pixel(0, 0))
            let count = 0
            let strongest = null
            let best = 0
            for (let y = 0; y < image.height; y++)
                for (let x = 0; x < image.width; x++) {
                    const c = Qt.color(image.pixel(x, y))
                    const d = Math.abs(c.r - bg.r) + Math.abs(c.g - bg.g) + Math.abs(c.b - bg.b)
                    if (d > 0.3) count++
                    if (d > best) { best = d; strongest = c }
                }
            return { count, first: strongest }
        }

        function icon(kind, color) {
            // Below the row of buttons, so nothing else is drawn over it.
            const item = createTemporaryQmlObject(
                'import QtQuick; import StickyNotes; ToolIcon { x: 100; y: 100; width: 48; height: 48 }', scene)
            item.color = color
            item.kind = kind
            created.push(item)
            return item
        }

        property var created: []
        function cleanup() {
            for (const item of created) item.destroy()
            created = []
        }

        // ---- icons ---------------------------------------------------------

        function test_every_icon_kind_draws_something() {
            for (const kind of ["save", "gear", "pencil", "robot"]) {
                const item = icon(kind, "black")
                tryVerify(() => inked(item).count > 40, 3000, kind + " should draw")
                item.visible = false
            }
        }

        function test_an_unknown_kind_draws_nothing() {
            const item = icon("nonsense", "black")
            wait(200)
            compare(inked(item).count, 0)
        }

        function test_the_icons_are_different_shapes() {
            const counts = {}
            for (const kind of ["save", "gear", "pencil", "robot"]) {
                const item = icon(kind, "black")
                tryVerify(() => inked(item).count > 40, 3000)
                counts[kind] = inked(item).count
                item.visible = false
            }
            const values = Object.values(counts)
            compare(new Set(values).size, values.length, JSON.stringify(counts))
        }

        function test_an_icon_is_drawn_in_its_color_and_follows_changes() {
            const item = icon("save", "#ff0000")
            tryVerify(() => inked(item).count > 40, 3000)
            let c = inked(item).first
            verify(c.r > 0.9 && c.g < 0.2 && c.b < 0.2, "red: " + c)
            item.color = "#0000ff"
            tryVerify(() => { const x = inked(item).first; return x.b > 0.9 && x.r < 0.2 }, 3000)
        }

        function test_an_icon_scales_with_its_size() {
            const small = createTemporaryQmlObject(
                'import QtQuick; import StickyNotes; ToolIcon { x: 100; y: 100; kind: "robot"; width: 16; height: 16; color: "black" }', scene)
            const large = createTemporaryQmlObject(
                'import QtQuick; import StickyNotes; ToolIcon { x: 200; y: 100; kind: "robot"; width: 64; height: 64; color: "black" }', scene)
            tryVerify(() => inked(small).count > 10 && inked(large).count > 10, 3000)
            verify(inked(large).count > inked(small).count * 4)
        }

        // ---- buttons -------------------------------------------------------

        function test_a_click_is_reported() {
            mouseClick(plain)
            compare(clickSpy.count, 1)
        }

        function test_the_tip_is_the_tooltip_and_the_accessible_name() {
            compare(plain.ToolTip.text, "Preferences")
            compare(plain.Accessible.name, "Preferences")
        }

        function test_a_button_with_no_tip_shows_no_tooltip() {
            const b = createTemporaryQmlObject(
                'import QtQuick; import StickyNotes; IconButton { glyph: "gear" }', scene)
            b.x = 300
            b.y = 100
            mouseMove(b, 5, 5)
            wait(50)
            verify(!b.ToolTip.visible, "nothing to show")
        }

        function test_a_checked_button_is_shown_in_the_primary_color() {
            compare(toggle.background.color.toString(), Qt.color("transparent").toString())
            compare(toggle.glyphColor.toString(), Theme.text.toString())
            mouseClick(toggle)
            verify(toggle.checked)
            compare(toggle.background.color.toString(), Theme.primary.toString())
            compare(toggle.glyphColor.toString(), Theme.textOnPrimary.toString())
            verify(Theme.contrast(toggle.glyphColor, toggle.background.color) >= 4.5)
        }

        function test_icons_follow_the_theme_mode() {
            const light = plain.glyphColor.toString()
            Theme.mode = "dark"
            verify(plain.glyphColor.toString() !== light)
            verify(Theme.contrast(plain.glyphColor, Theme.surface) >= 4.5)
        }

        // ---- the agent button ----------------------------------------------

        function test_the_agent_button_is_yellow_when_read_only_and_green_when_it_can_write() {
            compare(agent.background.color.toString(), Theme.agentReadOnly.toString())
            verify(agent.background.color.r > 0.9 && agent.background.color.g > 0.7 && agent.background.color.b < 0.3,
                   "yellow: " + agent.background.color)

            agent.badgeColor = Theme.agentReadWrite
            agent.badgeGlyphColor = Theme.textOnAgentReadWrite
            const green = agent.background.color
            verify(green.g > green.r && green.g > green.b, "green: " + green)
            verify(Theme.contrast(agent.glyphColor, agent.background.color) >= 4.5)
        }

        function test_the_agent_glyph_is_readable_on_both_colors_in_both_modes() {
            for (const mode of ["light", "dark"]) {
                Theme.mode = mode
                verify(Theme.contrast(Theme.textOnAgentReadOnly, Theme.agentReadOnly) >= 4.5, mode)
                verify(Theme.contrast(Theme.textOnAgentReadWrite, Theme.agentReadWrite) >= 4.5, mode)
            }
        }

        function test_the_agent_button_reports_clicks() {
            const spy = createTemporaryQmlObject(
                'import QtTest; SignalSpy { }', scene)
            spy.target = agent
            spy.signalName = "clicked"
            mouseClick(agent)
            compare(spy.count, 1)
        }
    }
}
