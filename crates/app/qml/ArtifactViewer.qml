import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StickyNotes

// A window that shows one artifact: Markdown as formatted text, an image
// that fits the window or at its actual size. Links in Markdown are shown but
// not followed. Created by Main.qml; `show(info)` takes the JSON from
// `BoardController.artifactJson`.
ApplicationWindow {
    id: viewer

    property string name: ""
    property string kind: ""            // "markdown" or "image"
    property string text: ""
    property string source: ""
    property bool fit: true

    readonly property bool isImage: kind === "image"

    // A file path as a URL that Image can load.
    function fileUrl(path) {
        const encoded = encodeURI(path.replace(/\\/g, "/"))
            .replace(/#/g, "%23").replace(/\?/g, "%3F")
        return encoded.startsWith("/") ? "file://" + encoded : "file:///" + encoded
    }

    function showArtifact(info) {
        name = info.name
        kind = info.kind
        text = info.text || ""
        source = info.kind === "image" ? fileUrl(info.path) : ""
        show()
        raise()
    }

    width: isImage ? 900 : 720
    height: isImage ? 700 : 640
    minimumWidth: 320
    minimumHeight: 240
    title: name + " — Sticky Notes"
    color: Theme.background

    palette {
        window: Theme.surface
        windowText: Theme.text
        base: Theme.fieldBackground
        text: Theme.text
        button: Theme.controlBackground
        buttonText: Theme.text
        highlight: Theme.primary
        highlightedText: Theme.textOnPrimary
        link: Theme.link
    }

    header: ToolBar {
        visible: viewer.isImage
        implicitHeight: visible ? 40 : 0
        background: Rectangle { color: Theme.surface }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            Label {
                objectName: "imageInfo"
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: Theme.subtleText
                text: picture.status === Image.Ready
                    ? qsTr("%1 × %2 px").arg(picture.sourceSize.width).arg(picture.sourceSize.height)
                    : ""
            }
            Button {
                objectName: "fitButton"
                text: viewer.fit ? qsTr("Actual size") : qsTr("Fit to window")
                onClicked: viewer.fit = !viewer.fit
            }
        }
    }

    // Markdown
    ScrollView {
        id: textScroll
        objectName: "markdownView"
        anchors.fill: parent
        visible: !viewer.isImage
        contentWidth: availableWidth

        TextEdit {
            objectName: "markdownText"
            width: textScroll.availableWidth
            padding: 20
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.MarkdownText
            text: viewer.text
            color: Theme.text
            selectionColor: Theme.primary
            selectedTextColor: Theme.textOnPrimary
        }
    }

    // Image
    Flickable {
        id: flick
        objectName: "imageView"
        anchors.fill: parent
        visible: viewer.isImage
        clip: true
        contentWidth: Math.max(picture.width, width)
        contentHeight: Math.max(picture.height, height)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        ScrollBar.horizontal: ScrollBar {}

        Image {
            id: picture
            objectName: "picture"
            source: viewer.isImage ? viewer.source : ""
            asynchronous: true
            // Only ever shrinks to fit; small images are not blown up.
            readonly property real scaleToFit: sourceSize.width > 0
                ? Math.min(1, flick.width / sourceSize.width, flick.height / sourceSize.height) : 1
            readonly property real shown: viewer.fit ? scaleToFit : 1
            width: sourceSize.width * shown
            height: sourceSize.height * shown
            x: Math.max(0, (flick.width - width) / 2)
            y: Math.max(0, (flick.height - height) / 2)
            smooth: true
        }

        Label {
            anchors.centerIn: parent
            visible: picture.status === Image.Error
            text: qsTr("This image could not be loaded.")
            color: Theme.danger
        }
    }
}
