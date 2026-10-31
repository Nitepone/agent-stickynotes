import QtQuick
import QtQuick.Controls.Fusion
import QtQuick.Layouts
import StickyNotes

// Preferences > Editor: spell checking in the task editor, and how the draft
// agent (which proposes requirements and criteria) is run. Emits what the user
// picked; the owner applies and saves it, then feeds the new values back in.
PreferencesSection {
    id: section

    title: qsTr("Editor")

    property bool spellCheck: true
    property bool spellAvailable: true          // false when no dictionary was found
    property string draftAgent: "claude_code"
    property string draftSystemPrompt: ""
    property string draftModel: ""              // "" is the agent's own default
    property string draftEffort: ""

    signal spellCheckChosen(bool enabled)
    signal draftAgentChosen(string agent)
    signal draftSystemPromptChosen(string prompt)
    signal draftModelChosen(string model)
    signal draftEffortChosen(string effort)

    // The prompt is saved shortly after typing stops, and when the field loses
    // focus or the page is left, rather than on every keystroke.
    function savePrompt() {
        saveTimer.stop()
        if (promptField.text !== section.draftSystemPrompt)
            section.draftSystemPromptChosen(promptField.text)
    }
    onVisibleChanged: if (!visible) savePrompt()

    Timer {
        id: saveTimer
        interval: 600
        onTriggered: section.savePrompt()
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            x: 32
            y: 24
            width: Math.min(scroll.availableWidth - 64, 640)
            spacing: 14

            Label {
                text: qsTr("Spell check")
                font.pixelSize: 22
                font.bold: true
                color: Theme.text
            }
            CheckBox {
                id: spellBox
                objectName: "spellCheckBox"
                text: qsTr("Underline misspelled words in the task editor")
                checked: section.spellCheck
                // Checked state is driven by the setting, not by clicking.
                onToggled: {
                    section.spellCheckChosen(checked)
                    checked = Qt.binding(() => section.spellCheck)
                }
            }
            Label {
                objectName: "noDictionary"
                Layout.fillWidth: true
                visible: !section.spellAvailable
                wrapMode: Text.Wrap
                color: Theme.warning
                text: qsTr("No dictionary was found, so nothing is underlined. Install a Hunspell dictionary (for example hunspell-en-us), or set STICKYNOTES_DICT_DIR to a folder with a .aff and .dic file.")
            }

            Label {
                Layout.topMargin: 12
                text: qsTr("Draft agent")
                font.pixelSize: 22
                font.bold: true
                color: Theme.text
            }
            Label {
                Layout.fillWidth: true
                text: qsTr("Proposes requirements and acceptance criteria from a task's descriptions. Changes apply to the next draft.")
                wrapMode: Text.Wrap
                color: Theme.subtleText
            }

            SectionLabel { text: qsTr("Agent type") }
            ComboBox {
                id: agentBox
                objectName: "agentBox"
                Layout.preferredWidth: 260
                textRole: "label"
                valueRole: "value"
                model: [{ value: "claude_code", label: qsTr("Claude Code (subshell)") }]
                onActivated: section.draftAgentChosen(currentValue)
                Binding {
                    target: agentBox
                    property: "currentIndex"
                    value: agentBox.count >= 0 ? Math.max(0, agentBox.indexOfValue(section.draftAgent)) : 0
                }
            }

            SectionLabel { text: qsTr("System prompt") }
            Label {
                Layout.fillWidth: true
                text: qsTr("Added to the built-in prompt, which already asks for requirements and criteria in the format the app reads. Use it for tone, language or house style.")
                wrapMode: Text.Wrap
                color: Theme.subtleText
                font.pixelSize: 12
            }
            FormTextArea {
                id: promptField
                objectName: "promptField"
                Layout.fillWidth: true
                Layout.minimumHeight: 110
                placeholderText: qsTr("For example: Write in British English. Keep each item short.")
                text: section.draftSystemPrompt
                onTextChanged: if (activeFocus) saveTimer.restart()
                onActiveFocusChanged: if (!activeFocus) section.savePrompt()
            }

            // Options that belong to the selected agent type.
            ColumnLayout {
                objectName: "claudeCodeOptions"
                Layout.fillWidth: true
                visible: section.draftAgent === "claude_code"
                spacing: 14

                SectionLabel { text: qsTr("Model") }
                ComboBox {
                    id: modelBox
                    objectName: "modelBox"
                    Layout.preferredWidth: 260
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { value: "", label: qsTr("Claude Code's default") },
                        { value: "fable", label: qsTr("Fable") },
                        { value: "opus", label: qsTr("Opus") },
                        { value: "sonnet", label: qsTr("Sonnet") },
                        { value: "haiku", label: qsTr("Haiku") }
                    ]
                    onActivated: section.draftModelChosen(currentValue)
                    Binding {
                        target: modelBox
                        property: "currentIndex"
                        value: modelBox.count >= 0 ? Math.max(0, modelBox.indexOfValue(section.draftModel)) : 0
                    }
                }

                SectionLabel { text: qsTr("Thinking level") }
                ComboBox {
                    id: effortBox
                    objectName: "effortBox"
                    Layout.preferredWidth: 260
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { value: "", label: qsTr("Claude Code's default") },
                        { value: "low", label: qsTr("Low") },
                        { value: "medium", label: qsTr("Medium") },
                        { value: "high", label: qsTr("High") },
                        { value: "xhigh", label: qsTr("Extra high") },
                        { value: "max", label: qsTr("Max") }
                    ]
                    onActivated: section.draftEffortChosen(currentValue)
                    Binding {
                        target: effortBox
                        property: "currentIndex"
                        value: effortBox.count >= 0 ? Math.max(0, effortBox.indexOfValue(section.draftEffort)) : 0
                    }
                }
            }
        }
    }
}
