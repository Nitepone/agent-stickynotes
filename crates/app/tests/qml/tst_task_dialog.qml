import QtQuick
import QtQuick.Controls.Fusion
import QtTest
import StickyNotes
import TestSupport

Item {
    id: scene
    width: 1000
    height: 900

    readonly property string longText: "This requirement is intentionally long so that it cannot possibly fit on one line of the dialog and must wrap onto several lines instead of scrolling sideways."

    TaskDialog {
        id: dialog
        relationOptions: [
            { value: "blocks", label: "blocks" },
            { value: "blocked_by", label: "is blocked by" },
            { value: "relates_to", label: "relates to" },
        ]
        linkCandidates: [
            { id: "t1", columnTitle: "Backlog", text: "the task itself", label: "Backlog \u2014 the task itself" },
            { id: "t2", columnTitle: "Backlog", text: "Write the docs", label: "Backlog \u2014 Write the docs" },
            { id: "t3", columnTitle: "Done", text: "Ship it", label: "Done \u2014 Ship it" },
        ]
    }
    // Wired like Main.qml: the dialog only asks, the owner confirms.
    ConfirmDialog { id: confirm }
    Connections {
        target: dialog
        function onUndoDraftRequested() {
            confirm.ask("Undo the draft?", "text", "Undo draft", true, () => dialog.undoDraft())
        }
    }
    SignalSpy { id: undoSpy; target: dialog; signalName: "undoDraftRequested" }
    SignalSpy { id: openSpy; target: dialog; signalName: "openTaskRequested" }
    SignalSpy { id: artifactSpy; target: dialog; signalName: "artifactClicked" }
    SignalSpy { id: attachSpy; target: dialog; signalName: "attachRequested" }
    SignalSpy { id: pasteSpy; target: dialog; signalName: "pasteRequested" }
    SignalSpy { id: generateSpy; target: dialog; signalName: "generateRequested" }
    SignalSpy { id: cancelSpy; target: dialog; signalName: "cancelGenerationRequested" }

    TestCase {
        name: "TaskDialog"
        when: windowShown

        function taskJson(requirements, criteria, references) {
            return JSON.stringify({
                id: "t1", number: 7, columnId: "c0", description: "d", extendedDescription: "",
                requirements: requirements,
                criteria: criteria,
                references: references || [],
                updatedAt: "2026-01-01T00:00:00Z",
            })
        }

        function open(requirements, criteria, references) {
            dialog.openTask(taskJson(requirements, criteria, references), "Backlog")
            waitForRendering(dialog.contentItem)
        }

        function init() {
            openSpy.clear()
            artifactSpy.clear()
            generateSpy.clear()
            cancelSpy.clear()
            undoSpy.clear()
            dialog.categories = []
            dialog.generating = false
            dialog.generatorName = "Claude Code"
        }
        function cleanup() { confirm.close(); dialog.close() }

        function fields(name) {
            return TestHelpers.findAllByName(dialog.contentItem, name)
        }

        function form() { return JSON.parse(dialog.formJson()) }

        function openWithArtifacts(artifacts) {
            dialog.openTask(JSON.stringify({
                id: "t1", number: 7, columnId: "c0", description: "d", extendedDescription: "",
                requirements: [], criteria: [], references: [], artifacts: artifacts,
                updatedAt: "2026-01-01T00:00:00Z",
            }), "Backlog")
            waitForRendering(dialog.contentItem)
        }

        function test_artifacts_are_listed_and_open_on_click() {
            openWithArtifacts([
                { id: "a1", name: "plan.md", kind: "markdown", byAgent: true },
                { id: "a2", name: "flow.png", kind: "image", byAgent: false },
            ])
            const links = fields("artifactLink")
            compare(links.length, 2)
            compare(links[0].text, "plan.md")
            compare(fields("noArtifacts")[0].visible, false)
            mouseClick(links[1])
            compare(artifactSpy.count, 1)
            compare(artifactSpy.signalArguments[0][0], "flow.png")
        }

        function test_each_artifact_shows_its_type_and_a_pdf_opens_through_the_same_signal() {
            openWithArtifacts([
                { id: "a1", name: "plan.md", kind: "markdown" },
                { id: "a2", name: "flow.png", kind: "image" },
                { id: "a3", name: "datasheet.pdf", kind: "pdf" },
            ])
            compare(fields("artifactKind").map(l => l.text), ["Markdown", "Image", "PDF"])
            // clicked() rather than mouseClick: a real click scrolls the dialog,
            // and the tests after this one expect it at the top.
            fields("artifactLink")[2].clicked()
            compare(artifactSpy.signalArguments[0][0], "datasheet.pdf")
        }

        function test_artifact_metadata_and_the_attach_button() {
            openWithArtifacts([
                { id: "a1", name: "plan.md", kind: "markdown", byAgent: true, addedBy: "claude-code",
                  stage: "Backlog", addedAt: "2026-03-05T10:12:00Z" },
                { id: "a2", name: "mine.png", kind: "image", byAgent: false, addedBy: "user", stage: "Doing",
                  addedAt: "2026-03-05T10:12:00Z" },
                { id: "a3", name: "old.md", kind: "markdown", byAgent: true },
                { id: "a4", name: "older.md", kind: "markdown", byAgent: false },
            ])
            const meta = fields("artifactMeta")
            verify(meta[0].text.indexOf("claude-code") === 0, meta[0].text)
            verify(meta[0].text.indexOf("in Backlog") > 0, meta[0].text)
            verify(meta[1].text.indexOf("You") === 0 && meta[1].text.indexOf("in Doing") > 0, meta[1].text)
            compare(meta[2].text, "added by an agent")
            compare(meta[3].visible, false)
            for (const m of meta)
                verify(m.text.indexOf("undefined") < 0 && m.text.indexOf("Invalid") < 0, m.text)

            // The real file chooser is replaced by a stub.
            dialog.chooser = { open: () => dialog.attachRequested(dialog.taskId, "file:///tmp/x.md") }
            const button = fields("attachButton")[0]
            verify(button.visible)
            button.clicked()   // may be scrolled out of view in the test window
            compare(attachSpy.count, 1)
            compare(attachSpy.signalArguments[0][0], "t1")
            dialog.attachError = "too big"
            compare(fields("attachError")[0].visible, true)
            dialog.close()
        }

        function test_dropping_files_requests_each_one_and_the_target_is_highlighted() {
            openWithArtifacts([])
            const highlight = fields("dropHighlight")[0]
            compare(highlight.visible, false)
            dialog.dragOver = true
            compare(highlight.visible, true)
            dialog.dragOver = false
            attachSpy.clear()
            dialog.attachError = "old"
            dialog.dropFiles(["file:///tmp/a.md", "file:///tmp/b.png", "file:///tmp/c.exe"])
            compare(attachSpy.count, 3)
            compare(attachSpy.signalArguments[0][0], "t1")
            compare(String(attachSpy.signalArguments[2][1]), "file:///tmp/c.exe")
            compare(dialog.attachError, "")
            // Refusals from the owner are listed one per line.
            dialog.attachFailed("c.exe: not accepted")
            dialog.attachFailed("d.zip: not accepted")
            compare(dialog.attachError, "c.exe: not accepted\nd.zip: not accepted")
            dialog.close()
        }

        function test_ctrl_v_attaches_unless_a_text_field_has_focus() {
            openWithArtifacts([])
            pasteSpy.clear()
            dialog.forceActiveFocus()
            verify(!dialog.textFocused)
            keyClick(Qt.Key_V, Qt.ControlModifier)
            compare(pasteSpy.count, 1)
            compare(pasteSpy.signalArguments[0][0], "t1")

            // In a text field Ctrl+V pastes text and nothing is attached.
            fields("descriptionField")[0].forceActiveFocus()
            verify(dialog.textFocused)
            keyClick(Qt.Key_V, Qt.ControlModifier)
            compare(pasteSpy.count, 1)
            dialog.close()
        }

        function test_new_task_dialog_attaches_nothing_and_says_why() {
            dialog.openNew({ id: "c0", title: "Backlog" })
            waitForRendering(dialog.contentItem)
            attachSpy.clear()
            pasteSpy.clear()
            dialog.dropFiles(["file:///tmp/a.md"])
            dialog.pasteFromClipboard()
            compare(attachSpy.count, 0)
            compare(pasteSpy.count, 0)
            verify(dialog.attachError !== "")
            compare(fields("attachError")[0].visible, true)
            dialog.close()
        }

        function test_attach_button_is_hidden_when_creating() {
            dialog.openNew({ id: "c0", title: "Backlog" })
            waitForRendering(dialog.contentItem)
            compare(fields("attachButton")[0].visible, false)
        }

        function test_no_artifacts_says_so_and_artifacts_are_not_part_of_the_form() {
            openWithArtifacts([])
            compare(fields("artifactLink").length, 0)
            compare(fields("noArtifacts")[0].visible, true)
            openWithArtifacts([{ id: "a1", name: "plan.md", kind: "markdown", byAgent: false }])
            verify(!("artifacts" in form()), "saving the form must not touch artifacts")
        }

        function test_long_requirement_wraps_and_grows() {
            open(["short", scene.longText], [])
            const [brief, lengthy] = fields("requirementField")
            verify(brief && lengthy)
            verify(lengthy.lineCount > 1, "long text should wrap, got " + lengthy.lineCount + " line(s)")
            verify(lengthy.height > brief.height, "wrapped field should be taller")
            compare(lengthy.contentWidth <= lengthy.width, true)
        }

        function test_field_grows_as_text_is_typed() {
            open([""], [])
            const [field] = fields("requirementField")
            const before = field.height
            field.text = scene.longText
            waitForRendering(dialog.contentItem)
            verify(field.height > before)
            field.text = "short again"
            waitForRendering(dialog.contentItem)
            compare(field.height, before)
        }

        function test_criteria_wrap_too() {
            open([], [{ id: "k1", text: scene.longText, done: false }])
            const [field] = fields("criterionField")
            verify(field.lineCount > 1)
        }

        function test_controls_align_with_first_line() {
            open([scene.longText], [{ id: "k1", text: scene.longText, done: true }])
            const [reqField] = fields("requirementField")
            const [remove] = fields("removeRequirement")
            const [critField] = fields("criterionField")
            const [check] = fields("criterionCheck")
            const [removeCrit] = fields("removeCriterion")
            verify(reqField.height > remove.height, "field should be taller than its button")
            // Buttons sit at the top of their rows, not vertically centred.
            compare(remove.mapToItem(reqField.parent, 0, 0).y, 0)
            compare(check.mapToItem(critField.parent, 0, 0).y, 0)
            compare(removeCrit.mapToItem(critField.parent, 0, 0).y, 0)
        }

        function test_enter_does_not_insert_line_break() {
            open(["one"], [{ id: "k1", text: "crit", done: false }])
            for (const name of ["requirementField", "criterionField"]) {
                const [field] = fields(name)
                field.forceActiveFocus()
                field.cursorPosition = field.text.length
                keyClick(Qt.Key_Return)
                keyClick(Qt.Key_Enter)
                verify(field.text.indexOf("\n") < 0, name + " must not contain a line break")
            }
            compare(form().requirements, ["one"])
            compare(form().criteria[0].text, "crit")
        }

        function test_pasted_newlines_become_spaces() {
            open(["x"], [])
            const [field] = fields("requirementField")
            field.text = "first line\nsecond line\n\nthird"
            compare(field.text, "first line second line third")
            compare(form().requirements, ["first line second line third"])
        }

        function test_edits_reach_the_form_json() {
            open(["a"], [{ id: "k1", text: "c", done: false }])
            const [req] = fields("requirementField")
            const [crit] = fields("criterionField")
            req.text = "a edited"
            crit.text = "c edited"
            compare(form().requirements, ["a edited"])
            compare(form().criteria[0].text, "c edited")
            compare(form().criteria[0].id, "k1")
        }

        // ---- references ----

        readonly property var blockedByDocs: [{
            taskId: "t2", relation: "blocked_by", relationLabel: "is blocked by",
            description: "Write the docs", columnTitle: "Backlog" }]

        function test_references_are_listed_and_in_the_form() {
            open([], [], blockedByDocs)
            compare(fields("referenceRelation").length, 1)
            compare(fields("referenceRelation")[0].text, "is blocked by")
            compare(fields("referenceLink")[0].text, "Write the docs")
            compare(form().references, [{ task: "t2", relation: "blocked_by" }])
        }

        function test_clicking_a_reference_requests_that_task() {
            open([], [], blockedByDocs)
            mouseClick(fields("referenceLink")[0])
            compare(openSpy.count, 1)
            compare(openSpy.signalArguments[0][0], "t2")
        }

        function test_remove_reference() {
            open([], [], blockedByDocs)
            mouseClick(fields("removeReference")[0])
            compare(fields("referenceRelation").length, 0)
            compare(form().references, [])
        }

        function test_add_reference_with_dropdowns() {
            open([], [])
            const [relation] = fields("relationBox")
            const [target] = fields("targetBox")
            const [add] = fields("addReference")
            verify(!add.enabled, "Add needs a chosen task")
            relation.currentIndex = 0
            target.currentIndex = 1
            verify(add.enabled)
            mouseClick(add)
            compare(form().references, [{ task: "t3", relation: "blocks" }])
            compare(fields("referenceLink")[0].text, "Ship it")
            compare(target.currentIndex, -1)
        }

        function test_a_task_cannot_link_to_itself() {
            open([], [])
            const [target] = fields("targetBox")
            compare(target.count, 2)
            for (let i = 0; i < target.count; i++)
                verify(target.valueAt(i) !== "t1")
        }

        function test_adding_an_existing_target_changes_its_relation() {
            open([], [], blockedByDocs)
            dialog.addReference("t2", "relates_to")
            compare(form().references, [{ task: "t2", relation: "relates_to" }])
            compare(fields("referenceRelation").length, 1)
        }

        function test_new_tasks_cannot_be_linked_yet() {
            dialog.openNew({ id: "c0", title: "Backlog" })
            waitForRendering(dialog.contentItem)
            verify(!("references" in form()), "create form must not carry references")
            verify(!fields("addReference")[0].visible)
        }

        function test_isEdited_tracks_changes_to_references() {
            open([], [], blockedByDocs)
            verify(!dialog.isEdited())
            mouseClick(fields("removeReference")[0])
            verify(dialog.isEdited())
        }

        // ---- drafting with an LLM ----

        function noteText() { return fields("generationNote")[0].text }

        function test_generate_is_disabled_without_a_description() {
            open([], [])
            const [button] = fields("generateButton")
            verify(button.enabled)
            const [description] = TestHelpers.findWhere(dialog.contentItem, c =>
                c.hasOwnProperty("placeholderText") && c.placeholderText.indexOf("sticky-note") >= 0)
            description.text = "   "
            verify(!button.enabled, "needs a description")
        }

        function test_generate_sends_the_current_form() {
            open(["Use HTTPS"], [{ id: "k1", text: "Can sign in", done: true }])
            mouseClick(fields("generateButton")[0])
            compare(generateSpy.count, 1)
            const sent = JSON.parse(generateSpy.signalArguments[0][0])
            compare(sent.description, "d")
            compare(sent.requirements, ["Use HTTPS"])
            compare(sent.criteria[0].text, "Can sign in")
        }

        function test_progress_and_cancel_are_shown_while_generating() {
            open([], [])
            verify(fields("generateButton")[0].visible)
            verify(!fields("cancelGeneration")[0].visible)
            dialog.generating = true
            verify(!fields("generateButton")[0].visible)
            verify(fields("generatingIndicator")[0].running)
            verify(fields("generatingLabel")[0].text.indexOf("Claude Code") >= 0)
            mouseClick(fields("cancelGeneration")[0])
            compare(cancelSpy.count, 1)
        }

        function test_closing_while_generating_cancels() {
            open([], [])
            dialog.generating = true
            dialog.close()
            compare(cancelSpy.count, 1)
        }

        function test_closing_when_idle_does_not_cancel() {
            open([], [])
            dialog.close()
            compare(cancelSpy.count, 0)
        }

        function test_draft_is_added_alongside_existing_items_and_not_saved() {
            open(["Use HTTPS"], [{ id: "k1", text: "Can sign in", done: true }])
            dialog.applyDraft(["Hash passwords"], ["Wrong password is rejected", "Account locks after 5 tries"])
            const f = form()
            compare(f.requirements, ["Use HTTPS", "Hash passwords"])
            compare(f.criteria.length, 3)
            compare(f.criteria[0].id, "k1")
            compare(f.criteria[0].done, true, "existing criteria are untouched")
            compare(f.criteria[1], { id: "", text: "Wrong password is rejected", done: false })
            verify(dialog.isEdited(), "drafted items are unsaved edits")
            compare(noteText(), "Added 1 requirement and 2 acceptance criteria below. Review and edit them, then Save.")
        }

        function test_an_empty_draft_says_so() {
            open([], [])
            dialog.applyDraft([], [])
            compare(fields("requirementField").length, 0)
            verify(noteText().indexOf("Nothing new") === 0)
            verify(!dialog.isEdited())
        }

        function test_errors_are_shown_and_cleared_by_the_next_attempt() {
            open([], [])
            dialog.showGenerationError("Claude Code was not found.")
            compare(noteText(), "Claude Code was not found.")
            mouseClick(fields("generateButton")[0])
            compare(fields("generationNote")[0].visible, false)
        }

        function test_drafted_items_can_be_edited_like_any_other() {
            open([], [])
            dialog.applyDraft(["Hash passwords"], [])
            fields("requirementField")[0].text = "Hash passwords with argon2"
            compare(form().requirements, ["Hash passwords with argon2"])
        }

        // ---- category from a draft, and the layout around it ----

        function openCategorized(category, requirements, criteria) {
            dialog.categories = ["Backend", "UI"]
            dialog.openTask(JSON.stringify({
                id: "t1", number: 7, columnId: "c0", description: "d", extendedDescription: "",
                category: category, requirements: requirements || [], criteria: criteria || [],
                references: [], updatedAt: "2026-01-01T00:00:00Z",
            }), "Backlog")
            waitForRendering(dialog.contentItem)
        }

        function sectionY(text) {
            const [label] = TestHelpers.findWhere(dialog.contentItem, c =>
                c.hasOwnProperty("text") && c.text === text && c.visible && c.width > 0)
            verify(label, "section " + text)
            return label.mapToItem(dialog.contentItem.contentItem, 0, 0).y
        }

        function test_the_draft_button_sits_above_the_category_section() {
            openCategorized("", [], [])
            const draft = fields("generateButton")[0]
            const draftY = draft.mapToItem(dialog.contentItem.contentItem, 0, 0).y
            verify(draftY < sectionY("Category"), "draft button above Category")
            verify(draftY > sectionY("Extended description"), "and below the descriptions")
            verify(fields("categoryBox")[0].mapToItem(dialog.contentItem.contentItem, 0, 0).y > draftY)
        }

        function test_a_draft_fills_an_empty_category() {
            openCategorized("", [], [])
            dialog.applyDraft(["R"], [], "UI", false)
            compare(form().category, "UI")
            compare(fields("categoryBox")[0].currentIndex, 1, "the combo shows the board's entry")
            compare(fields("categoryBox")[0].editText, "UI")
            verify(noteText().indexOf("Category set to") >= 0)
            verify(!fields("categoryNote")[0].visible)
        }

        function test_a_category_the_user_already_chose_is_kept_silently() {
            openCategorized("Backend", [], [])
            dialog.applyDraft(["R"], [], "UI", false)
            compare(form().category, "Backend")
            verify(noteText().indexOf("Category") < 0, noteText())
            verify(!fields("categoryNote")[0].visible)
        }

        function test_an_invalid_category_is_flagged_and_changes_nothing() {
            openCategorized("", [], [])
            dialog.applyDraft(["R"], ["C"], null, true)
            compare(form().category, "")
            compare(form().requirements, ["R"], "the rest of the draft is applied")
            verify(fields("categoryNote")[0].visible)
            // The next attempt clears the flag.
            mouseClick(fields("generateButton")[0])
            verify(!fields("categoryNote")[0].visible)
        }

        function test_no_flag_when_the_user_has_a_category_even_if_the_draft_had_none() {
            openCategorized("UI", [], [])
            dialog.applyDraft(["R"], [], null, true)
            verify(!fields("categoryNote")[0].visible)
        }

        function test_the_category_box_still_works_after_a_draft() {
            openCategorized("", [], [])
            dialog.applyDraft(["R"], [], "UI", false)
            const box = fields("categoryBox")[0]
            box.currentIndex = 0
            box.activated(0)
            compare(form().category, "Backend")
            mouseClick(fields("clearCategory")[0])
            compare(form().category, "")
            box.contentItem.forceActiveFocus()
            box.contentItem.selectAll()
            for (const ch of "Docs")
                keyClick(ch)
            compare(form().category, "Docs")
        }

        // ---- undoing a draft ----

        function undoButton() { return fields("undoDraftButton")[0] }

        function test_undo_is_only_offered_after_a_draft() {
            openCategorized("", ["Keep"], [])
            verify(!undoButton().visible)
            dialog.applyDraft([], [], null, false)
            verify(!undoButton().visible, "an empty draft changes nothing, so nothing to undo")
            dialog.applyDraft(["R"], [], null, false)
            verify(undoButton().visible)
            const left = undoButton().mapToItem(dialog.contentItem.contentItem, 0, 0)
            const draft = fields("generateButton")[0].mapToItem(dialog.contentItem.contentItem, 0, 0)
            verify(Math.abs(left.y - draft.y) < 4, "next to the draft button")
            verify(left.x > draft.x)
        }

        function test_clicking_undo_asks_first_and_changes_nothing() {
            openCategorized("", ["Keep"], [{ id: "k1", text: "Old", done: true }])
            dialog.applyDraft(["R"], ["C"], "UI", false)
            mouseClick(undoButton())
            compare(undoSpy.count, 1)
            tryCompare(confirm, "visible", true)
            compare(form().requirements, ["Keep", "R"])
            compare(form().category, "UI")
        }

        function test_cancelling_the_confirmation_keeps_the_draft() {
            openCategorized("", ["Keep"], [])
            dialog.applyDraft(["R"], ["C"], "UI", false)
            mouseClick(undoButton())
            tryCompare(confirm, "visible", true)
            wait(50)
            mouseClick(TestHelpers.findWhere(confirm.footer, i => i.text === "Cancel" && i.visible)[0])
            tryCompare(confirm, "visible", false)
            compare(form().requirements, ["Keep", "R"])
            compare(form().criteria.length, 1)
            compare(form().category, "UI")
            verify(undoButton().visible, "still undoable")
        }

        function test_confirming_restores_the_state_before_the_draft() {
            openCategorized("", ["Keep"], [{ id: "k1", text: "Old", done: true }])
            const before = form()
            dialog.applyDraft(["R"], ["C"], "UI", false)
            verify(form().requirements.length === 2)
            mouseClick(undoButton())
            tryCompare(confirm, "visible", true)
            wait(50)
            mouseClick(TestHelpers.findWhere(confirm.footer, i => i.text === "Undo draft" && i.visible)[0])
            tryCompare(confirm, "visible", false)
            compare(form(), before, "requirements, criteria (ids, done) and category as before")
            verify(!undoButton().visible)
            verify(!dialog.isEdited())
        }

        function test_undo_works_after_the_drafted_items_were_shown_and_edited() {
            openCategorized("", [], [])
            dialog.applyDraft(["R"], ["C"], "UI", false)
            waitForRendering(dialog.contentItem)
            compare(fields("requirementField").length, 1, "the item is in the dialog's list")
            fields("requirementField")[0].text = "edited"
            dialog.undoDraft()
            compare(fields("requirementField").length, 0)
            compare(fields("criterionField").length, 0)
            compare(form().category, "")
        }

        function test_the_snapshot_is_dropped_when_the_dialog_closes() {
            openCategorized("", [], [])
            dialog.applyDraft(["R"], [], null, false)
            dialog.close()
            verify(!dialog.hasDraftSnapshot)
            openCategorized("", [], [])
            verify(!undoButton().visible)
        }

        // ---- task number ----

        function test_the_task_number_is_shown_and_read_only() {
            open([], [])
            const [label] = fields("taskNumber")
            compare(label.text, "#7")
            verify(label.visible)
            // A plain label: nothing to type into, and not part of the form.
            verify(!label.hasOwnProperty("readOnly") && !label.hasOwnProperty("cursorPosition"))
            verify(!("number" in form()), "the number is never submitted")
            verify(!("taskNumber" in form()))
        }

        function test_a_new_task_has_no_number_yet() {
            dialog.openNew({ id: "c0", title: "Backlog" })
            waitForRendering(dialog.contentItem)
            verify(!fields("taskNumber")[0].visible)
        }

        // ---- category ----

        function openWithCategory(category) {
            dialog.categories = ["Backend", "UI"]
            dialog.openTask(JSON.stringify({
                id: "t1", number: 7, columnId: "c0", description: "d", extendedDescription: "",
                category: category, requirements: [], criteria: [], references: [],
                updatedAt: "2026-01-01T00:00:00Z",
            }), "Backlog")
            waitForRendering(dialog.contentItem)
            return fields("categoryBox")[0]
        }

        function typeCategory(box, text) {
            box.contentItem.forceActiveFocus()
            verify(box.contentItem.activeFocus, "the editor has focus")
            box.contentItem.selectAll()
            for (const ch of text)
                keyClick(ch)
        }

        function test_the_dropdown_lists_the_categories_used_on_the_board() {
            const box = openWithCategory("")
            compare(box.count, 2)
            compare(box.model, ["Backend", "UI"])
            compare(box.textAt(0), "Backend")
            compare(box.textAt(1), "UI")
            compare(box.editable, true)
            compare(form().category, "")
        }

        function test_a_task_opens_with_its_category_selected() {
            const box = openWithCategory("UI")
            compare(box.currentIndex, 1)
            compare(box.editText, "UI")
            compare(form().category, "UI")
            verify(!dialog.isEdited())
        }

        function test_choosing_from_the_dropdown_sets_the_category() {
            const box = openWithCategory("")
            box.currentIndex = 0
            box.activated(0)
            compare(form().category, "Backend")
            verify(dialog.isEdited())
        }

        function test_typing_a_new_category_adds_it_trimmed() {
            const box = openWithCategory("")
            typeCategory(box, "  Docs ")
            compare(form().category, "Docs")
            keyClick(Qt.Key_Return)
            compare(box.editText, "Docs")
            compare(box.currentIndex, -1)
        }

        function test_typing_an_existing_category_in_another_case_selects_it() {
            const box = openWithCategory("")
            typeCategory(box, "ui")
            // Even before leaving the box the saved value uses the existing spelling.
            compare(form().category, "UI")
            keyClick(Qt.Key_Return)
            compare(box.currentIndex, 1)
            compare(box.editText, "UI")
            compare(form().category, "UI")
            // Leaving the box settles it too.
            typeCategory(box, "bACKEND")
            box.focus = false
            dialog.settleCategory()
            compare(box.currentIndex, 0)
            compare(box.editText, "Backend")
        }

        function test_the_clear_button_removes_the_category() {
            const box = openWithCategory("UI")
            const [clear] = fields("clearCategory")
            compare(clear.enabled, true)
            mouseClick(clear)
            compare(box.editText, "")
            compare(form().category, "")
            compare(clear.enabled, false)
            verify(dialog.isEdited())
        }

        function test_new_categories_arriving_while_open_keep_what_was_typed() {
            const box = openWithCategory("")
            typeCategory(box, "Docs")
            dialog.categories = ["Backend", "Docs", "UI"]
            compare(box.count, 3)
            compare(form().category, "Docs")
        }

        function test_a_new_task_starts_without_a_category() {
            openWithCategory("UI")
            dialog.close()
            dialog.openNew({ id: "c0", title: "Backlog" })
            waitForRendering(dialog.contentItem)
            compare(form().category, "")
            compare(fields("categoryBox")[0].editText, "")
        }
    }
}
