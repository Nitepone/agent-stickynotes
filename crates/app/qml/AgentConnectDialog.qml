import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// How to connect an agent to the board's MCP server: one independent,
// collapsible section per client. The owner supplies the strings and runs the
// connection check; this dialog does not talk to the controller. Ask for a
// check with `testRequested(client)` and answer with `setCheckResult`.
StickyDialog {
    id: dialog

    property string setupCommand: ""          // Claude Code CLI
    property string desktopProjectJson: ""    // Claude Code Desktop, .mcp.json
    property string desktopBridgeJson: ""     // Claude Desktop, claude_desktop_config.json
    property string opencodeJson: ""          // OpenCode, opencode.json
    property string endpoint: ""
    property bool agentWrite: false
    property bool reducedMotion: false

    signal testRequested(string client)

    // `client` is "cli", "desktop" or "opencode".
    function setCheckResult(client, ok, message) {
        const test = { cli: cliTest, desktop: desktopTest, opencode: opencodeTest }[client]
        if (!test) return
        test.message = message || ""
        test.status = ok ? "ok" : "failed"
    }
    function requestTest(client, test) {
        test.status = "testing"
        dialog.testRequested(client)
    }
    // Screenshot aid.
    function expandAll() {
        cliSection.expanded = desktopSection.expanded = opencodeSection.expanded = true
    }
    function resetChecks() {
        for (const t of [cliTest, desktopTest, opencodeTest]) { t.status = "idle"; t.message = "" }
    }

    title: qsTr("Connect Agent")
    maxWidth: 760
    acceptText: ""
    rejectText: qsTr("Close")

    contentItem: ScrollView {
        id: scroll
        implicitHeight: Math.min(sections.implicitHeight,
                                 Math.max(240, (dialog.parent ? dialog.parent.height : 720) - 160))
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            id: sections
            width: scroll.availableWidth
            spacing: 8

            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: qsTr("Pick your client and follow its steps. The agent server runs while this window is open.")
            }

            CollapsibleSection {
                id: cliSection
                objectName: "cliSection"
                title: qsTr("Claude Code CLI")
                expanded: true
                reducedMotion: dialog.reducedMotion

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: qsTr("Run this once in a terminal to register the board's MCP server with Claude Code.")
                }
                CodeBlock {
                    id: cliCommand
                    objectName: "cliCommand"
                    text: dialog.setupCommand
                    copyLabel: qsTr("Copy command")
                }
                ConnectionTest {
                    id: cliTest
                    objectName: "cliTest"
                    onTestRequested: dialog.requestTest("cli", cliTest)
                }
            }

            CollapsibleSection {
                id: desktopSection
                objectName: "desktopSection"
                title: qsTr("Claude Code Desktop")
                reducedMotion: dialog.reducedMotion

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: qsTr("Needs only the Claude desktop app. In the project's root folder, create or edit .mcp.json so it contains:")
                }
                CodeBlock {
                    id: desktopProject
                    objectName: "desktopProjectJson"
                    text: dialog.desktopProjectJson
                    copyLabel: qsTr("Copy JSON")
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: qsTr("Then open that folder in the Code tab and approve the \"stickynotes\" server when asked. Keep .mcp.json out of version control: it contains the token.")
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.bold: true
                    text: qsTr("Also for the Claude chat tab (needs Node.js)")
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: qsTr("The chat tab only starts local programs, so it reaches this server through the mcp-remote bridge, which npx downloads on first use. Merge this into claude_desktop_config.json (Settings > Developer > Edit Config; macOS ~/Library/Application Support/Claude, Windows %APPDATA%\\Claude, Linux ~/.config/Claude), then restart Claude:")
                }
                CodeBlock {
                    id: desktopBridge
                    objectName: "desktopBridgeJson"
                    text: dialog.desktopBridgeJson
                    copyLabel: qsTr("Copy JSON")
                }
                ConnectionTest {
                    id: desktopTest
                    objectName: "desktopTest"
                    onTestRequested: dialog.requestTest("desktop", desktopTest)
                }
            }

            CollapsibleSection {
                id: opencodeSection
                objectName: "opencodeSection"
                title: qsTr("OpenCode")
                reducedMotion: dialog.reducedMotion

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: qsTr("Add this to opencode.json in the project root, or to ~/.config/opencode/opencode.json for every project:")
                }
                CodeBlock {
                    id: opencodeBlock
                    objectName: "opencodeJson"
                    text: dialog.opencodeJson
                    copyLabel: qsTr("Copy JSON")
                }
                ConnectionTest {
                    id: opencodeTest
                    objectName: "opencodeTest"
                    onTestRequested: dialog.requestTest("opencode", opencodeTest)
                }
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtleText
                text: qsTr("REST API: %1/api/v1 (same bearer token)\nAgent write access is currently %2. Toggle it from the Agent menu.")
                      .arg(dialog.endpoint)
                      .arg(dialog.agentWrite ? qsTr("enabled") : qsTr("disabled"))
            }
        }
    }
    onOpened: {
        for (const b of [cliCommand, desktopProject, desktopBridge, opencodeBlock]) b.reset()
        resetChecks()
    }
}
