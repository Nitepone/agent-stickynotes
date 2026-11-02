import QtQuick

// Turns a column's tasks into the rows the column shows: plain cards and, for
// tasks that share a category, a header followed by the stack's cards. Pure
// logic with no visuals, so it can be tested on its own. The stored task order
// is never changed; only what is shown is regrouped.
//
// A stack needs two or more tasks with the same category (compared ignoring
// case) in this column. It sits where its first member is, and its members
// follow the header in their stored relative order. Uncategorized tasks and a
// lone categorized task are plain cards.
QtObject {
    id: model

    property string columnId: ""
    property var tasks: []
    // The column's full stored order when `tasks` is a filtered subset of it;
    // empty means `tasks` is everything. Positions are always stored ones.
    property var allTasks: []

    // [{ kind: "card", task, stackKey, showCategory }
    //  | { kind: "header", stackKey, category, count, ids }]  (ids: the stack's
    // task ids in stored order)
    // `stackKey` is "" for a card that is not in a stack.
    readonly property var rows: build(tasks, columnId)

    // Identifies a stack across board refreshes; the view keeps its
    // collapsed/expanded state under this key.
    function stackKey(columnId, category) {
        return columnId + "\u001f" + normalized(category)
    }

    function normalized(category) {
        return (category || "").trim().toLowerCase()
    }

    function build(tasks, columnId) {
        const counts = {}
        for (const t of tasks) {
            const n = normalized(t.category)
            if (n !== "")
                counts[n] = (counts[n] || 0) + 1
        }
        const rows = []
        const emitted = {}
        for (const t of tasks) {
            const n = normalized(t.category)
            if (n === "" || counts[n] < 2) {
                rows.push({ kind: "card", task: t, stackKey: "", showCategory: n !== "" })
                continue
            }
            if (emitted[n])
                continue
            emitted[n] = true
            const key = stackKey(columnId, n)
            rows.push({ kind: "header", stackKey: key, category: t.category.trim(), count: counts[n],
                          ids: tasks.filter(m => normalized(m.category) === n).map(m => m.id) })
            for (const member of tasks) {
                if (normalized(member.category) === n)
                    rows.push({ kind: "card", task: member, stackKey: key, showCategory: false })
            }
        }
        return rows
    }

    // Position in the stored task order for a card dropped before the
    // `index`-th shown card. `shownIds` lists the shown cards from top to
    // bottom (collapsed members are not shown), without the dragged one; an
    // index past the end means the end of the column.
    // `draggedId` is one id or an array of ids (a whole stack being moved).
    function isDragged(draggedId, id) {
        return typeof draggedId === "string" ? draggedId === id : draggedId.indexOf(id) >= 0
    }

    function storedPosition(shownIds, index, draggedId) {
        const others = (allTasks.length > 0 ? allTasks : tasks).filter(t => !isDragged(draggedId, t.id))
        if (index >= shownIds.length)
            return others.length
        const at = others.findIndex(t => t.id === shownIds[index])
        return at < 0 ? others.length : at
    }
}
