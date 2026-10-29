import QtQuick

// Decides which notes glow, and how strongly.
//
// A note glows when an agent changed it after the user last interacted with
// the app. The glow holds at full strength until the user's first interaction
// after that change, then fades out over `fadeMs`. Notes the user changed
// themselves, and notes the user has already seen, do not glow.
//
// The owner calls `sync(board)` whenever the board changes and `interact()`
// on user activity. All times are milliseconds since the Unix epoch and can
// be passed explicitly, which keeps this testable.
QtObject {
    id: tracker

    // When the user last used the app, saved from the previous session. 0
    // means there was none (a first launch): then nothing counts as unseen.
    property double savedInteraction: 0
    // When the user last interacted. Starts from the saved time, so the very
    // first sync of a session already knows what the user has seen.
    property double lastInteraction: savedInteraction > 0 ? savedInteraction : Date.now()
    property int fadeMs: Theme.glowFadeMs
    // The clock the intensities are computed against.
    property double now: Date.now()
    // note id -> { changedAt, edited, fadeStart (null until the user returns) }
    property var records: ({})

    readonly property bool fading: anyFading(records)

    function anyFading(map) {
        for (const id in map)
            if (map[id].fadeStart !== null)
                return true
        return false
    }

    // Take the agent changes from the board (`board.columns[].tasks[].agentChange`).
    function sync(board, nowMs) {
        const next = {}
        for (const column of board.columns)
            for (const task of column.tasks) {
                const change = task.agentChange
                if (!change)
                    continue
                const known = records[task.id]
                if (known && known.changedAt === change.at)
                    next[task.id] = known              // same change: keep its fade
                else if (change.at > lastInteraction)
                    next[task.id] = { changedAt: change.at, edited: change.kind === "edited", fadeStart: null }
                // else: the user has interacted since; already seen
            }
        records = next
        now = nowMs === undefined ? Date.now() : nowMs
    }

    // The user did something: start fading whatever is glowing.
    function interact(nowMs) {
        const t = nowMs === undefined ? Date.now() : nowMs
        lastInteraction = t
        const next = {}
        let started = false
        for (const id in records) {
            const r = records[id]
            if (r.fadeStart === null) {
                next[id] = { changedAt: r.changedAt, edited: r.edited, fadeStart: t }
                started = true
            } else {
                next[id] = r
            }
        }
        if (started)
            records = next
        now = t
    }

    // 0 (no glow) to 1 (full glow).
    function intensity(id) {
        const r = records[id]
        if (!r)
            return 0
        if (r.fadeStart === null)
            return 1
        return Math.max(0, Math.min(1, 1 - (now - r.fadeStart) / fadeMs))
    }

    // Whether the agent edited the note's content (as opposed to moving it).
    function edited(id) {
        const r = records[id]
        return !!r && r.edited
    }

    // Advance the clock and forget fades that have finished.
    function tick(nowMs) {
        now = nowMs
        let next = null
        for (const id in records) {
            const r = records[id]
            if (r.fadeStart !== null && now - r.fadeStart >= fadeMs) {
                if (!next)
                    next = Object.assign({}, records)
                delete next[id]
            }
        }
        if (next)
            records = next
    }

    // Only runs while something is fading.
    property Timer ticker: Timer {
        interval: 200
        repeat: true
        running: tracker.fading
        onTriggered: tracker.tick(Date.now())
    }
}
