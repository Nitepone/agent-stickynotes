import QtQuick
import QtTest
import StickyNotes
import TestSupport

Item {
    id: scene
    width: 400
    height: 300

    Component { id: trackerComponent; GlowTracker { } }
    Component { id: edgeComponent; GlowEdge { width: 264; height: 80 } }
    Item { id: dragLayer }
    GlowTracker { id: longTracker }

    // A column long enough to scroll, every note glowing.
    ColumnView {
        id: longColumn
        x: 20
        width: 284
        height: 320
        dragLayer: dragLayer
        glowTracker: longTracker
        column: ({
            id: "c", title: "Long", description: "",
            tasks: Array.from({ length: 40 }, (_, i) => ({
                id: "n" + i, number: i + 1, cardText: "note " + i, done: 0, total: 0 }))
        })
    }

    TestCase {
        name: "GlowTracker"
        when: windowShown

        readonly property double t0: 1700000000000          // the user's last interaction

        // A tracker with a fixed clock: the real-time ticker is switched off.
        function makeTracker(lastInteraction) {
            const tracker = createTemporaryObject(trackerComponent, scene)
            tracker.ticker.running = false
            tracker.lastInteraction = lastInteraction === undefined ? t0 : lastInteraction
            return tracker
        }

        function board(tasks) {
            return { columns: [{ tasks: tasks }] }
        }

        function task(id, at, kind) {
            return { id: id, agentChange: at === null ? null : { at: at, kind: kind || "moved" } }
        }

        // ---- which notes glow ------------------------------------------

        function test_a_note_changed_since_the_last_interaction_glows() {
            const tracker = makeTracker()
            tracker.sync(board([task("a", t0 + 5000)]), t0 + 6000)
            compare(tracker.intensity("a"), 1)
        }

        function test_a_note_not_changed_since_the_last_interaction_does_not_glow() {
            const tracker = makeTracker()
            tracker.sync(board([task("old", t0 - 1000), task("none", null), task("same", t0)]), t0 + 6000)
            compare(tracker.intensity("old"), 0, "changed before the user was last here")
            compare(tracker.intensity("none"), 0, "never changed by an agent")
            compare(tracker.intensity("same"), 0, "not strictly after")
            compare(tracker.intensity("unknown"), 0)
        }

        function test_only_edited_notes_get_the_sheen() {
            const tracker = makeTracker()
            tracker.sync(board([task("e", t0 + 1, "edited"), task("m", t0 + 1, "moved"),
                                task("c", t0 + 1, "created"), task("p", t0 + 1, "progress")]), t0 + 2)
            verify(tracker.edited("e"))
            for (const id of ["m", "c", "p"]) {
                verify(!tracker.edited(id), id)
                compare(tracker.intensity(id), 1, id + " still glows")
            }
        }

        // ---- fading ----------------------------------------------------

        function test_the_glow_holds_until_the_user_comes_back_then_fades_over_20_seconds() {
            const tracker = makeTracker()
            tracker.sync(board([task("a", t0 + 5000)]), t0 + 6000)
            // The user is away: no matter how long, it stays at full strength.
            tracker.tick(t0 + 600000)
            compare(tracker.intensity("a"), 1)

            const back = t0 + 700000
            tracker.interact(back)
            compare(tracker.intensity("a"), 1, "interacting does not remove it immediately")
            tracker.tick(back + 1000)
            verify(tracker.intensity("a") > 0.9 && tracker.intensity("a") < 1)
            tracker.tick(back + 10000)
            verify(Math.abs(tracker.intensity("a") - 0.5) < 0.001, "half way after 10 s")
            tracker.tick(back + 19000)
            verify(tracker.intensity("a") > 0 && tracker.intensity("a") < 0.06, "nearly gone")
            tracker.tick(back + 20000)
            compare(tracker.intensity("a"), 0, "gone after 20 s")
            compare(Object.keys(tracker.records).length, 0, "and forgotten")
            verify(!tracker.fading)
        }

        function test_the_fade_is_smooth_and_only_goes_down() {
            const tracker = makeTracker()
            tracker.sync(board([task("a", t0 + 1)]), t0 + 2)
            tracker.interact(t0 + 100)
            let previous = 1.01
            for (let s = 0; s <= 20; s++) {
                tracker.tick(t0 + 100 + s * 1000)
                const now = tracker.intensity("a")
                verify(now < previous, "second " + s + ": " + now + " should be below " + previous)
                previous = now
            }
        }

        function test_the_fade_length_is_20_seconds() {
            compare(Theme.glowFadeMs, 20000)
            compare(makeTracker().fadeMs, 20000)
        }

        function test_more_interaction_does_not_restart_or_extend_the_fade() {
            const tracker = makeTracker()
            tracker.sync(board([task("a", t0 + 1)]), t0 + 2)
            tracker.interact(t0 + 1000)
            tracker.interact(t0 + 6000)            // still fading from the first
            tracker.tick(t0 + 11000)
            verify(Math.abs(tracker.intensity("a") - 0.5) < 0.001, "fade started at the first interaction")
        }

        function test_syncing_again_keeps_the_fade_but_a_new_change_restarts_it() {
            const tracker = makeTracker()
            const b = board([task("a", t0 + 1)])
            tracker.sync(b, t0 + 2)
            tracker.interact(t0 + 1000)
            tracker.tick(t0 + 11000)
            tracker.sync(b, t0 + 11000)            // e.g. another note changed
            verify(Math.abs(tracker.intensity("a") - 0.5) < 0.001, "same change: fade carries on")

            tracker.sync(board([task("a", t0 + 12000)]), t0 + 12000)   // the agent touched it again
            compare(tracker.intensity("a"), 1, "a new change glows at full strength again")
        }

        // ---- who changed it --------------------------------------------

        function test_a_change_by_the_user_clears_the_glow() {
            const tracker = makeTracker()
            tracker.sync(board([task("a", t0 + 1)]), t0 + 2)
            compare(tracker.intensity("a"), 1)
            tracker.sync(board([task("a", null)]), t0 + 3)      // the core clears the marker
            compare(tracker.intensity("a"), 0)
        }

        function test_a_deleted_note_stops_glowing() {
            const tracker = makeTracker()
            tracker.sync(board([task("a", t0 + 1), task("b", t0 + 1)]), t0 + 2)
            tracker.sync(board([task("b", t0 + 1)]), t0 + 3)
            compare(tracker.intensity("a"), 0)
            compare(tracker.intensity("b"), 1)
        }

        // ---- after a restart ---------------------------------------------

        function test_after_a_restart_state_follows_the_saved_last_interaction() {
            // A fresh tracker, as after launching: only what the file and the
            // saved time say.
            const b = board([task("before", t0 - 5000), task("after", t0 + 5000)])
            const tracker = makeTracker(t0)
            tracker.sync(b, t0 + 600000)
            compare(tracker.intensity("before"), 0, "seen in the last session")
            compare(tracker.intensity("after"), 1, "changed while the app was closed")
        }

        function test_a_note_seen_before_a_restart_does_not_glow_again() {
            const tracker = makeTracker()
            const b = board([task("a", t0 + 5000)])
            tracker.sync(b, t0 + 6000)
            tracker.interact(t0 + 9000)
            // Restart: the saved time is the last interaction.
            const relaunched = makeTracker(tracker.lastInteraction)
            relaunched.sync(b, t0 + 100000)
            compare(relaunched.intensity("a"), 0)
        }

        // The saved time must count from the very first sync, before any
        // interaction in this session.
        function test_a_saved_interaction_time_is_known_before_the_first_sync() {
            const tracker = createTemporaryObject(trackerComponent, scene, { savedInteraction: t0 })
            tracker.ticker.running = false
            compare(tracker.lastInteraction, t0)
            tracker.sync(board([task("seen", t0 - 1), task("unseen", t0 + 1)]), t0 + 100000)
            compare(tracker.intensity("seen"), 0)
            compare(tracker.intensity("unseen"), 1)
        }

        function test_a_first_launch_marks_nothing_as_unseen() {
            const before = Date.now()
            const tracker = createTemporaryObject(trackerComponent, scene, { savedInteraction: 0 })
            tracker.ticker.running = false
            verify(tracker.lastInteraction >= before, "starts from now")
            tracker.sync(board([task("old", before - 60000, "edited")]), Date.now())
            compare(tracker.intensity("old"), 0)
        }

        function test_interacting_updates_the_last_interaction_time() {
            const tracker = makeTracker()
            tracker.interact(t0 + 1234)
            compare(tracker.lastInteraction, t0 + 1234)
        }

        function test_the_ticker_runs_only_while_something_fades() {
            const tracker = createTemporaryObject(trackerComponent, scene)
            tracker.lastInteraction = t0
            verify(!tracker.ticker.running)
            tracker.sync(board([task("a", t0 + 1)]), t0 + 2)
            verify(!tracker.ticker.running, "a steady glow needs no clock")
            tracker.interact(t0 + 5)
            verify(tracker.ticker.running)
            tracker.tick(t0 + 5 + 20000)
            verify(!tracker.ticker.running)
        }
    }

    TestCase {
        name: "GlowCulling"
        when: windowShown

        function init() {
            longTracker.ticker.running = false
            const tasks = []
            for (let i = 0; i < 40; i++)
                tasks.push({ id: "n" + i, agentChange: { at: 5000, kind: "edited" } })
            longTracker.lastInteraction = 0
            longTracker.sync({ columns: [{ tasks: tasks }] }, 6000)
        }

        function flickable() {
            const found = TestHelpers.findWhere(longColumn, c =>
                c.hasOwnProperty("contentY") && c.hasOwnProperty("flickableDirection"))
            return found.length ? found[found.length - 1] : null
        }

        function comet(i) {
            const card = findChild(longColumn, "card-n" + i)
            return findChild(card, "cometAnimation")
        }

        function test_only_notes_near_the_visible_area_animate() {
            const flick = flickable()
            flick.contentY = 0
            verify(comet(0).running, "first note is in view")
            verify(comet(2).running)
            verify(!comet(39).running, "last note is far below the view")
            verify(!comet(20).running)
        }

        function test_scrolled_out_notes_keep_their_static_glow() {
            const card = findChild(longColumn, "card-n39")
            const edge = findChild(card, "glowEdge")
            verify(edge.visible, "still glowing")
            compare(findChild(edge, "comet").visible, false)
            verify(findChild(edge, "glowRing"))
        }

        function test_scrolling_moves_the_animation_to_the_notes_now_in_view() {
            const flick = flickable()
            flick.contentY = flick.contentHeight - flick.height
            verify(comet(39).running, "now in view")
            verify(!comet(0).running, "scrolled away")
            flick.contentY = 0
            verify(comet(0).running)
            verify(!comet(39).running)
        }

        function test_only_a_handful_of_animations_run_at_once() {
            flickable().contentY = 0
            let running = 0
            for (let i = 0; i < 40; i++)
                if (comet(i).running) running++
            verify(running > 0 && running <= 8, running + " animations for a column of 40")
        }
    }

    TestCase {
        name: "GlowEdge"
        when: windowShown

        function edge(props) {
            return createTemporaryObject(edgeComponent, scene, props)
        }

        function find(root, name) {
            return TestHelpers.findAllByName(root, name, true)
        }

        function test_nothing_is_drawn_or_animated_without_glow() {
            const e = edge({ intensity: 0, edited: true })
            verify(!e.visible)
            verify(!find(e, "cometAnimation")[0].running, "no animation cost for idle notes")
            verify(!find(e, "sheenAnimation")[0].running)
        }

        function test_a_glowing_note_shows_a_green_border_and_a_moving_highlight() {
            const e = edge({ intensity: 1 })
            verify(e.visible)
            const rings = find(e, "glowRing")
            compare(rings.length, 3)
            for (const ring of rings)
                compare(ring.border.color.toString(), Theme.glow.toString(), "the glow color comes from Theme")
            // Green: the green channel dominates.
            verify(Theme.glow.g > Theme.glow.r && Theme.glow.g > Theme.glow.b)
            verify(find(e, "comet")[0].visible)
            verify(find(e, "cometAnimation")[0].running)
        }

        function test_the_highlight_goes_round_once_every_2_to_4_seconds() {
            const animation = find(edge({ intensity: 1 }), "cometAnimation")[0]
            verify(animation.loops < 0, "repeats forever")
            compare(animation.duration, Theme.glowRotationMs)
            verify(animation.duration >= 2000 && animation.duration <= 4000, "got " + animation.duration)
        }

        function test_edited_notes_get_a_sheen_that_moves_left_to_right() {
            const e = edge({ intensity: 1, edited: true })
            const sheen = find(e, "sheen")[0]
            verify(sheen.parent.visible)
            verify(find(e, "sheenAnimation")[0].running)
            const sweep = find(e, "sheenAnimation")[0].animations[0]
            verify(sweep.from < 0, "starts off the left edge")
            verify(sweep.to > e.width, "ends off the right edge")
            compare(sweep.property, "x")
        }

        function test_notes_that_were_not_edited_get_no_sheen() {
            const e = edge({ intensity: 1, edited: false })
            verify(!find(e, "sheen")[0].parent.visible)
            verify(!find(e, "sheenAnimation")[0].running)
        }

        function test_reduced_motion_leaves_a_static_glow() {
            const e = edge({ intensity: 1, edited: true, reducedMotion: true })
            verify(e.visible)
            for (const ring of find(e, "glowRing"))
                verify(ring.visible)
            verify(!find(e, "comet")[0].visible, "no rotation")
            verify(!find(e, "cometAnimation")[0].running)
            verify(!find(e, "sheen")[0].parent.visible, "no sheen")
            verify(!find(e, "sheenAnimation")[0].running)
        }

        function test_turning_reduced_motion_on_stops_a_running_animation() {
            const e = edge({ intensity: 1, edited: true })
            verify(find(e, "cometAnimation")[0].running)
            e.reducedMotion = true
            verify(!find(e, "cometAnimation")[0].running)
            verify(!find(e, "sheenAnimation")[0].running)
            e.reducedMotion = false
            verify(find(e, "cometAnimation")[0].running)
        }

        function test_the_whole_effect_fades_with_the_intensity() {
            const e = edge({ intensity: 1 })
            compare(e.opacity, 1)
            e.intensity = 0.4
            compare(e.opacity, 0.4)
            e.intensity = 0
            verify(!e.visible)
        }

        function test_the_glow_never_takes_input() {
            verify(!edge({ intensity: 1 }).enabled)
        }
    }
}
