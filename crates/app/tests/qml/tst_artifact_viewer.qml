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

        function test_file_urls_are_encoded() {
            compare(viewer.fileUrl("/home/a b/p#1/x.png"), "file:///home/a%20b/p%231/x.png")
            compare(viewer.fileUrl("C:\\proj\\x.png"), "file:///C:/proj/x.png")
        }
    }
}
