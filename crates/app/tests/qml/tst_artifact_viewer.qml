import QtQuick
import QtQuick.Controls
import QtTest
import StickyNotes

Item {
    width: 400
    height: 300

    ArtifactViewer { id: viewer }

    TestCase {
        name: "ArtifactViewer"
        when: windowShown

        function child(root, name) {
            let found = null
            ;(function walk(item) {
                for (const c of item.children) {
                    if (c.objectName === name) found = c
                    walk(c)
                }
            })(root)
            return found
        }

        function cleanup() { viewer.close() }

        function test_shows_markdown_as_text() {
            viewer.showArtifact({ name: "notes.md", kind: "markdown", text: "# Title\n\nSome **bold** text." })
            tryCompare(viewer, "visible", true)
            compare(viewer.title, "notes.md \u2014 Sticky Notes")
            compare(child(viewer.contentItem, "markdownView").visible, true)
            compare(child(viewer.contentItem, "imageView").visible, false)
            const text = child(viewer.contentItem, "markdownText")
            compare(text.textFormat, TextEdit.MarkdownText)
            compare(text.readOnly, true)
            verify(text.text.indexOf("Title") >= 0)
            // Rendered, not raw: the heading marker is not in the displayed text.
            verify(text.getText(0, text.length).indexOf("#") < 0)
        }

        function test_shows_an_image_and_toggles_fit() {
            viewer.showArtifact({ name: "shot.png", kind: "image", text: null,
                                  path: Qt.resolvedUrl("pixel.png").toString().replace("file://", "") })
            tryCompare(viewer, "visible", true)
            compare(child(viewer.contentItem, "imageView").visible, true)
            compare(child(viewer.contentItem, "markdownView").visible, false)
            const picture = child(viewer.contentItem, "picture")
            tryCompare(picture, "status", Image.Ready)
            compare(viewer.fit, true)
            const fit = child(viewer.header, "fitButton")
            verify(fit !== null)
            fit.clicked()
            compare(viewer.fit, false)
            compare(picture.width, picture.sourceSize.width)
        }

        function test_large_images_shrink_to_fit_but_small_ones_do_not_grow() {
            viewer.showArtifact({ name: "wide.png", kind: "image", text: null,
                                  path: Qt.resolvedUrl("wide.png").toString().replace("file://", "") })
            const picture = child(viewer.contentItem, "picture")
            tryCompare(picture, "status", Image.Ready)
            verify(picture.sourceSize.width > viewer.width)
            verify(picture.width <= viewer.contentItem.width)
            compare(picture.shown, picture.scaleToFit)
        }

        readonly property string doc: "# Alpha\n\nFirst section about cats.\n\n```\n# not a heading\n```\n\n"
            + "## Beta *beta*\n\n" + "filler\n\n".repeat(60) + "# Gamma\n\nLast section about Cats."

        function open_doc() {
            viewer.showArtifact({ name: "doc.md", kind: "markdown", text: doc })
            tryCompare(viewer, "visible", true)
            tryCompare(viewer.headings, "length", 3)
        }

        function test_contents_lists_headings_but_not_code() {
            open_doc()
            compare(viewer.headings.map(h => h.title), ["Alpha", "Beta beta", "Gamma"])
            compare(viewer.headings.map(h => h.level), [1, 2, 1])
            const view = child(viewer.contentItem, "contentsView")
            compare(view.visible, true)
            compare(view.count, 3)
        }

        function test_clicking_a_contents_entry_scrolls_to_the_section() {
            open_doc()
            compare(viewer.scroller.contentY, 0)
            const view = child(viewer.contentItem, "contentsView")
            function entries() {
                const list = []
                for (const c of view.contentItem.children)
                    if (c.objectName === "contentsItem") list.push(c)
                return list.sort((a, b) => a.y - b.y)
            }
            tryVerify(() => entries().length === 3)
            const found = entries()
            mouseClick(found[2])
            verify(viewer.scroller.contentY > 100, "scrolled down to Gamma")
            compare(viewer.activeHeading, 2)
            mouseClick(found[0])
            verify(viewer.scroller.contentY < 30, "back at the top")
            compare(viewer.activeHeading, 0)
        }

        function test_documents_without_headings_have_no_contents() {
            viewer.showArtifact({ name: "p.md", kind: "markdown", text: "just text" })
            compare(viewer.headings.length, 0)
            compare(child(viewer.contentItem, "contentsView").visible, false)
            compare(child(viewer.header, "contentsButton").enabled, false)
        }

        function test_search_counts_matches_ignoring_case_and_steps_through_them() {
            open_doc()
            viewer.search("cats", true)
            compare(viewer.matches.length, 2)
            compare(viewer.currentMatch, 0)
            const text = child(viewer.contentItem, "markdownText")
            compare(text.selectedText, "cats")
            viewer.nextMatch()
            compare(viewer.currentMatch, 1)
            compare(text.selectedText, "Cats")
            verify(viewer.scroller.contentY > 100, "scrolled to the later match")
            viewer.nextMatch()
            compare(viewer.currentMatch, 0, "wraps around")
            viewer.previousMatch()
            compare(viewer.currentMatch, 1)
            viewer.search("zzz", true)
            compare(viewer.matches.length, 0)
            compare(child(viewer.header, "matchCount").text, "No matches")
        }

        function test_typing_in_the_search_field_searches() {
            open_doc()
            const field = child(viewer.header, "searchField")
            field.forceActiveFocus()
            keyClick("c"); keyClick("a"); keyClick("t")
            compare(viewer.matches.length, 2)
            compare(child(viewer.header, "matchCount").text, "1 of 2")
            keyClick(Qt.Key_Return)
            compare(viewer.currentMatch, 1)
            keyClick(Qt.Key_Return, Qt.ShiftModifier)
            compare(viewer.currentMatch, 0)
            keyClick(Qt.Key_Escape)
            compare(viewer.matches.length, 0)
        }

        function test_zoom_is_bounded_and_changes_the_text_size() {
            open_doc()
            const text = child(viewer.contentItem, "markdownText")
            const base = text.font.pixelSize
            viewer.zoomIn()
            verify(text.font.pixelSize > base)
            mouseClick(child(viewer.header, "zoomReset"))
            compare(viewer.zoom, 1)
            compare(text.font.pixelSize, base)
            for (let i = 0; i < 40; i++) viewer.zoomIn()
            compare(viewer.zoom, viewer.maxZoom)
            for (let i = 0; i < 60; i++) viewer.zoomOut()
            compare(viewer.zoom, viewer.minZoom)
            compare(child(viewer.header, "zoomOut").enabled, false)
        }

        function test_styles_change_the_look_and_are_reported() {
            open_doc()
            const text = child(viewer.contentItem, "markdownText")
            const spy = createTemporaryObject(spyComponent, viewer, { target: viewer })
            const box = child(viewer.header, "styleBox")
            compare(box.count, 4)
            compare(box.currentValue, "default")
            const base = text.font.pixelSize
            box.currentIndex = 1
            box.activated(1)
            compare(spy.count, 1)
            compare(spy.signalArguments[0][0], "reading")
            viewer.styleId = "reading"
            verify(text.font.pixelSize > base)
            verify(text.width <= 680)
            compare(box.currentValue, "reading")
            viewer.styleId = "nonsense"
            compare(text.font.pixelSize, base, "an unknown style falls back to the default")
            viewer.styleId = "default"
        }

        Component { id: spyComponent; SignalSpy { signalName: "styleChosen" } }

        function test_the_markdown_toolbar_is_hidden_for_images() {
            viewer.showArtifact({ name: "shot.png", kind: "image", text: null,
                                  path: Qt.resolvedUrl("pixel.png").toString().replace("file://", "") })
            compare(child(viewer.header, "markdownBar").visible, false)
            compare(child(viewer.header, "fitButton").visible, true)
        }

        function test_file_urls_are_encoded() {
            compare(viewer.fileUrl("/home/a b/p#1/x.png"), "file:///home/a%20b/p%231/x.png")
            compare(viewer.fileUrl("C:\\proj\\x.png"), "file:///C:/proj/x.png")
        }
    }
}
