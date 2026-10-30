import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StickyNotes

// A window that shows one artifact: Markdown as formatted text, an image
// that fits the window or at its actual size. Markdown has a toolbar (contents,
// search, zoom, display style) and a contents pane to jump between sections.
// Links in Markdown are shown but not followed. Created by Main.qml;
// `showArtifact(info)` takes the JSON from `BoardController.artifactJson`.
// The chosen style is reported with `styleChosen` and given back as `styleId`.
ApplicationWindow {
    id: viewer

    property string name: ""
    property string kind: ""            // "markdown" or "image"
    property string text: ""
    property string source: ""
    property bool fit: true

    // ---- Markdown display ----
    property string styleId: "default"
    property real zoom: 1
    property bool showContents: true
    property var headings: []           // [{title, level, position}] in document order
    property int activeHeading: -1
    property string query: ""
    property var matches: []            // start positions of the query in the text
    property int currentMatch: -1
    signal styleChosen(string id)

    readonly property bool isImage: kind === "image"
    readonly property real minZoom: 0.5
    readonly property real maxZoom: 3

    readonly property var styles: [
        { id: "default", label: qsTr("Default"), families: [], size: 15, maxWidth: 0 },
        { id: "reading", label: qsTr("Reading"),
          families: ["Georgia", "Charter", "Noto Serif", "DejaVu Serif", "serif"],
          size: 17, maxWidth: 680 },
        { id: "compact", label: qsTr("Compact"), families: [], size: 13, maxWidth: 0 },
        { id: "mono", label: qsTr("Monospace"),
          families: ["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"],
          size: 14, maxWidth: 0 },
    ]
    readonly property var displayStyle: {
        for (const s of styles)
            if (s.id === styleId) return s
        return styles[0]
    }

    // The first of `families` that is installed; "" keeps the default font.
    function pickFamily(families) {
        const installed = Qt.fontFamilies()
        for (const f of families)
            if (installed.indexOf(f) >= 0) return f
        return ""
    }

    function setZoom(value) {
        zoom = Math.max(minZoom, Math.min(maxZoom, Math.round(value * 100) / 100))
    }
    function zoomIn() { setZoom(zoom + 0.1) }
    function zoomOut() { setZoom(zoom - 0.1) }
    function zoomReset() { setZoom(1) }

    // The visible scroll area of the Markdown view.
    readonly property var scroller: textScroll.contentItem

    function scrollToPosition(pos) {
        const rect = markdownText.positionToRectangle(pos)
        const max = Math.max(0, scroller.contentHeight - scroller.height)
        scroller.contentY = Math.max(0, Math.min(max, rect.y - 8))
    }

    // ---- contents ----

    // Headings found in the Markdown source (ATX `#` headings outside code
    // fences), each located in the rendered text so a jump can scroll to it.
    property string outlineText: "\u0000"
    function rebuildOutline() {
        if (text === outlineText) return
        outlineText = text
        const found = []
        let fence = ""
        for (const line of text.split("\n")) {
            const marker = /^ {0,3}(`{3,}|~{3,})/.exec(line)
            if (marker) {
                if (fence === "") fence = marker[1][0]
                else if (marker[1][0] === fence) fence = ""
                continue
            }
            if (fence !== "") continue
            const m = /^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$/.exec(line)
            if (!m) continue
            const title = m[2].replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1").replace(/[*_`~]/g, "").trim()
            if (title !== "") found.push({ title: title, level: m[1].length, position: -1 })
        }
        const rendered = markdownText.getText(0, markdownText.length)
        let from = 0
        for (const h of found) {
            const at = rendered.indexOf(h.title, from)
            if (at >= 0) {
                h.position = at
                from = at + h.title.length
            }
        }
        headings = found.filter(h => h.position >= 0)
        updateActiveHeading()
    }

    function jumpToHeading(index) {
        if (index < 0 || index >= headings.length) return
        scrollToPosition(headings[index].position)
        activeHeading = index
    }

    function updateActiveHeading() {
        const top = scroller.contentY + 24
        let active = -1
        for (let i = 0; i < headings.length; i++) {
            if (headings[i].position > markdownText.length) break
            if (markdownText.positionToRectangle(headings[i].position).y <= top) active = i
            else break
        }
        activeHeading = active
    }

    // ---- search ----

    // Finds every case-insensitive match of `q`; `jump` selects the first one.
    function search(q, jump) {
        query = q
        const found = []
        if (q !== "") {
            const plain = markdownText.getText(0, markdownText.length).toLowerCase()
            const needle = q.toLowerCase()
            for (let at = plain.indexOf(needle); at >= 0; at = plain.indexOf(needle, at + needle.length))
                found.push(at)
        }
        matches = found
        if (found.length === 0) {
            currentMatch = -1
            markdownText.deselect()
        } else if (jump !== false || currentMatch < 0 || currentMatch >= found.length) {
            showMatch(0)
        } else {
            showMatch(currentMatch)
        }
    }

    function showMatch(index) {
        if (matches.length === 0) return
        currentMatch = (index + matches.length) % matches.length
        const start = matches[currentMatch]
        markdownText.select(start, start + query.length)
        const y = markdownText.positionToRectangle(start).y
        if (y < scroller.contentY || y > scroller.contentY + scroller.height - 40)
            scrollToPosition(start)
    }

    function nextMatch() { showMatch(currentMatch + 1) }
    function previousMatch() { showMatch(currentMatch - 1) }

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
        query = ""
        zoom = 1
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
        implicitHeight: 40
        background: Rectangle { color: Theme.surface }

        // Markdown: contents, search, zoom, style
        RowLayout {
            objectName: "markdownBar"
            visible: !viewer.isImage
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            ToolButton {
                objectName: "contentsButton"
                text: qsTr("Contents")
                checkable: true
                checked: viewer.showContents
                enabled: viewer.headings.length > 0
                onClicked: viewer.showContents = !viewer.showContents
            }
            TextField {
                id: searchField
                objectName: "searchField"
                Layout.fillWidth: true
                Layout.maximumWidth: 260
                placeholderText: qsTr("Search (Ctrl+F)")
                selectByMouse: true
                onTextChanged: viewer.search(text, true)
                Keys.onReturnPressed: (event) => {
                    if (event.modifiers & Qt.ShiftModifier) viewer.previousMatch()
                    else viewer.nextMatch()
                }
                Keys.onEscapePressed: {
                    text = ""
                    markdownText.forceActiveFocus()
                }
            }
            Label {
                objectName: "matchCount"
                color: Theme.subtleText
                visible: viewer.query !== ""
                text: viewer.matches.length === 0
                    ? qsTr("No matches")
                    : qsTr("%1 of %2").arg(viewer.currentMatch + 1).arg(viewer.matches.length)
            }
            ToolButton {
                objectName: "previousMatch"
                text: "\u2191"
                enabled: viewer.matches.length > 0
                onClicked: viewer.previousMatch()
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Previous match (Shift+Enter)")
            }
            ToolButton {
                objectName: "nextMatch"
                text: "\u2193"
                enabled: viewer.matches.length > 0
                onClicked: viewer.nextMatch()
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Next match (Enter)")
            }
            Item { Layout.fillWidth: true }
            ToolButton {
                objectName: "zoomOut"
                text: "\u2212"
                enabled: viewer.zoom > viewer.minZoom
                onClicked: viewer.zoomOut()
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Zoom out (Ctrl+\u2212)")
            }
            ToolButton {
                objectName: "zoomReset"
                text: Math.round(viewer.zoom * 100) + "%"
                onClicked: viewer.zoomReset()
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Reset zoom (Ctrl+0)")
            }
            ToolButton {
                objectName: "zoomIn"
                text: "+"
                enabled: viewer.zoom < viewer.maxZoom
                onClicked: viewer.zoomIn()
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Zoom in (Ctrl++)")
            }
            ComboBox {
                id: styleBox
                objectName: "styleBox"
                textRole: "label"
                valueRole: "id"
                model: viewer.styles
                currentIndex: Math.max(0, viewer.styles.findIndex(s => s.id === viewer.styleId))
                onActivated: viewer.styleChosen(currentValue)
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Display style")
            }
        }

        // Image: size and fit
        RowLayout {
            visible: viewer.isImage
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

    Shortcut { sequences: [StandardKey.Find]; enabled: !viewer.isImage
        onActivated: { searchField.forceActiveFocus(); searchField.selectAll() } }
    Shortcut { sequences: [StandardKey.ZoomIn, "Ctrl+="]; enabled: !viewer.isImage; onActivated: viewer.zoomIn() }
    Shortcut { sequences: [StandardKey.ZoomOut]; enabled: !viewer.isImage; onActivated: viewer.zoomOut() }
    Shortcut { sequences: ["Ctrl+0"]; enabled: !viewer.isImage; onActivated: viewer.zoomReset() }
    Shortcut { sequences: [StandardKey.FindNext]; enabled: !viewer.isImage; onActivated: viewer.nextMatch() }
    Shortcut { sequences: [StandardKey.FindPrevious]; enabled: !viewer.isImage; onActivated: viewer.previousMatch() }

    // Markdown: contents pane beside the text
    RowLayout {
        anchors.fill: parent
        visible: !viewer.isImage
        spacing: 0

        ListView {
            id: contents
            objectName: "contentsView"
            visible: viewer.showContents && viewer.headings.length > 0
            Layout.preferredWidth: 210
            Layout.fillHeight: true
            clip: true
            model: viewer.headings
            ScrollBar.vertical: ScrollBar {}
            Rectangle { z: -1; anchors.fill: parent; color: Theme.surface }
            header: Label {
                padding: 10
                text: qsTr("Contents")
                font.bold: true
                color: Theme.subtleText
            }
            delegate: ItemDelegate {
                objectName: "contentsItem"
                required property var modelData
                required property int index
                width: contents.width
                leftPadding: 10 + (modelData.level - 1) * 12
                highlighted: index === viewer.activeHeading
                text: modelData.title
                background: Rectangle {
                    color: parent.highlighted ? Theme.primary
                         : parent.hovered ? Theme.controlHover : Theme.surface
                }
                contentItem: Text {
                    text: parent.text
                    elide: Text.ElideRight
                    font.bold: parent.highlighted
                    color: parent.highlighted ? Theme.textOnPrimary : Theme.text
                }
                onClicked: viewer.jumpToHeading(index)
            }
        }
        Rectangle {
            visible: contents.visible
            Layout.fillHeight: true
            implicitWidth: 1
            color: Theme.fieldBorder
        }

        ScrollView {
            id: textScroll
            objectName: "markdownView"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth

            TextEdit {
                id: markdownText
                objectName: "markdownText"
                readonly property real column: viewer.displayStyle.maxWidth > 0
                    ? Math.min(textScroll.availableWidth, viewer.displayStyle.maxWidth * viewer.zoom)
                    : textScroll.availableWidth
                width: column
                x: Math.max(0, (textScroll.availableWidth - column) / 2)
                padding: 20
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.MarkdownText
                text: viewer.text
                color: Theme.text
                selectionColor: Theme.primary
                selectedTextColor: Theme.textOnPrimary
                font.pixelSize: Math.round(viewer.displayStyle.size * viewer.zoom)
                font.family: viewer.pickFamily(viewer.displayStyle.families)
                onTextChanged: viewer.rebuildOutline()

                // Ctrl + wheel zooms; a plain wheel scrolls as usual.
                WheelHandler {
                    acceptedModifiers: Qt.ControlModifier
                    onWheel: (event) => {
                        if (event.angleDelta.y > 0) viewer.zoomIn()
                        else if (event.angleDelta.y < 0) viewer.zoomOut()
                    }
                }
            }

            Connections {
                target: viewer.scroller
                function onContentYChanged() { viewer.updateActiveHeading() }
            }
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
