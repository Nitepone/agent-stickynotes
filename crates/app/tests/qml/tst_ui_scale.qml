import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

// The interface scale: the zoom shortcuts (real key events), and that cards,
// column headers and dialogs grow with it without clipping their text.
Item {
    id: scene
    width: 1000
    height: 700

    // Wired as Main.qml does: the shortcuts are off while an artifact viewer
    // shows, and a request sets the scale.
    ZoomActions {
        id: zoom
        current: Theme.scale
        active: !viewer.visible
        onScaleRequested: (value) => Theme.scale = value
    }
    ArtifactViewer { id: viewer }

    Item { id: dragLayer }
    TaskCard {
        id: card
        dragLayer: dragLayer
        x: 10
        y: 10
        task: ({ id: "t1", number: 7, cardText: "A task with a fairly long description that wraps",
                 done: 1, total: 3, category: "Backend", artifactCount: 2 })
    }
    ColumnView {
        id: column
        x: 320
        y: 10
        width: Theme.columnWidth
        height: 400
        dragLayer: dragLayer
        column: ({ id: "c0", title: "Backlog", description: "", tasks: [
            { id: "t1", number: 1, cardText: "first", done: 0, total: 0 } ] })
    }
    ConfirmDialog { id: confirm }

    TestCase {
        name: "UiScale"
        when: windowShown

        function init() { Theme.scale = 1 }
        function cleanup() {
            Theme.scale = 1
            viewer.close()
            confirm.close()
            // The viewer is a window of its own; keys go to the active one.
            scene.Window.window.requestActivate()
            tryVerify(() => scene.Window.window.active)
        }

        function zoomKey(key, modifiers) { keyClick(key, modifiers || Qt.ControlModifier) }

        // Every visible Text under `root` shows all of its text.
        function assertNoClippedText(root) {
            const isText = i => i.visible && i.truncated !== undefined && i.text !== "" && i.width > 0
            const texts = TestHelpers.findWhere(root, isText)
            if (isText(root))
                texts.push(root)
            verify(texts.length > 0, "no text under " + root)
            for (const t of texts) {
                verify(!t.truncated, "truncated: " + t.text)
                verify(t.contentWidth <= t.width + 1, "too wide: " + t.text)
            }
        }

        function test_keys_step_in_tenths() {
            zoomKey(Qt.Key_Equal)
            compare(Theme.scale, 1.1)
            zoomKey(Qt.Key_Equal)
            compare(Theme.scale, 1.2)
            zoomKey(Qt.Key_Minus)
            compare(Theme.scale, 1.1)
            keyClick(Qt.Key_Plus, Qt.ControlModifier)
            compare(Theme.scale, 1.2)
        }

        function test_scale_is_clamped_at_both_ends() {
            for (let i = 0; i < 15; i++)
                zoomKey(Qt.Key_Equal)
            compare(Theme.scale, 2.0)
            zoomKey(Qt.Key_Equal)
            compare(Theme.scale, 2.0)
            for (let i = 0; i < 20; i++)
                zoomKey(Qt.Key_Minus)
            compare(Theme.scale, 0.7)
            zoomKey(Qt.Key_Minus)
            compare(Theme.scale, 0.7)
        }

        function test_zero_resets() {
            zoomKey(Qt.Key_Equal)
            zoomKey(Qt.Key_Equal)
            zoomKey(Qt.Key_0)
            compare(Theme.scale, 1)
            zoomKey(Qt.Key_Minus)
            zoomKey(Qt.Key_0)
            compare(Theme.scale, 1)
        }

        function test_the_menu_item_shows_the_percentage() {
            compare(zoom.actualSizeAction.text, "&Actual Size (100%)")
            zoomKey(Qt.Key_Equal)
            compare(zoom.actualSizeAction.text, "&Actual Size (110%)")
        }

        function test_scale_helpers() {
            compare(Theme.px(10), 10)
            compare(Theme.fs(13), 13)
            compare(Theme.clampScale(5), 2)
            compare(Theme.clampScale(0.1), 0.7)
            compare(Theme.clampScale(NaN), 1)
            compare(Theme.steppedScale(0.7, -1), 0.7)
            compare(Theme.steppedScale(2, 1), 2)
            compare(Theme.steppedScale(1.5, 0), 1)
            Theme.scale = 1.5
            compare(Theme.px(10), 15)
            compare(Theme.fs(13), 20)
        }

        function test_card_column_header_and_dialog_grow_by_the_factor() {
            const cardHeight = card.height
            const cardWidth = card.width
            const title = TestHelpers.findByName(column, "title")
            const titleHeight = title.height
            const columnWidth = column.width
            confirm.ask("Delete?", "Really?", "Delete", true, () => {})
            tryCompare(confirm, "visible", true)
            wait(50)
            const dialogWidth = confirm.width
            confirm.close()

            Theme.scale = 1.5
            wait(50)
            // Rounded lengths and wrapped text allow a little slack.
            verify(Math.abs(card.width - cardWidth * 1.5) <= 2, "card width " + card.width)
            verify(card.height >= cardHeight * 1.3 && card.height <= cardHeight * 1.7, "card height " + card.height)
            compare(Theme.columnWidth, 426)
            verify(title.height > titleHeight, "column title height")
            verify(TestHelpers.findByName(column, "title").height <= titleHeight * 1.7)
            confirm.open()
            tryCompare(confirm, "visible", true)
            wait(50)
            compare(confirm.width, dialogWidth * 1.5)
            assertNoClippedText(card)
            assertNoClippedText(column)
            assertNoClippedText(confirm.contentItem)
        }

        function test_nothing_is_clipped_at_the_extremes() {
            for (const s of [0.7, 2.0]) {
                Theme.scale = s
                wait(50)
                card.width = Theme.columnWidth - Theme.px(20)
                column.width = Theme.columnWidth
                assertNoClippedText(card)
                assertNoClippedText(column)
            }
        }

        function test_open_viewer_owns_the_zoom_keys() {
            viewer.showArtifact({ name: "n.md", kind: "markdown", text: "# T\n\nbody",
                                  html: "<h1>T</h1><p>body</p>" })
            tryCompare(viewer, "visible", true)
            compare(zoom.active, false)
            compare(zoom.zoomInAction.enabled, false)
            compare(zoom.zoomOutAction.enabled, false)
            compare(zoom.actualSizeAction.enabled, false)
            // The app-level keys do nothing...
            zoomKey(Qt.Key_Equal)
            zoomKey(Qt.Key_Minus)
            compare(Theme.scale, 1)
            // ...and the viewer's own zoom shortcuts are enabled and distinct.
            const shortcuts = TestHelpers.findWhere(viewer.contentItem,
                c => c.sequences !== undefined && c.activated !== undefined, true)
            verify(shortcuts.some(s => s.enabled && s.sequences.length > 0))
            viewer.zoomIn()
            compare(viewer.zoom, 1.1)
            compare(Theme.scale, 1)

            viewer.close()
            tryCompare(viewer, "visible", false)
            compare(zoom.active, true)
            scene.Window.window.requestActivate()
            tryVerify(() => scene.Window.window.active)
            zoomKey(Qt.Key_Equal)
            compare(Theme.scale, 1.1)
        }

        function test_the_viewer_text_follows_the_app_scale() {
            viewer.showArtifact({ name: "n.md", kind: "markdown", text: "# T\n\nbody",
                                  html: "<h1>T</h1><p>body</p>" })
            tryCompare(viewer, "visible", true)
            const text = TestHelpers.findByName(viewer.contentItem, "markdownText")
            const base = text.font.pixelSize
            Theme.scale = 1.5
            compare(text.font.pixelSize, Math.round(base * 1.5))
            viewer.zoomIn()
            compare(text.font.pixelSize, Math.round(base * 1.5 * 1.1))
        }
    }
}
