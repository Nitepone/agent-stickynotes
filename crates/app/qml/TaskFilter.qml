import QtQuick

// What the board view hides: a text filter, a category filter and the "hide old
// tasks in the last column" option. View-only state with no visuals; the stored
// board and what agents see are never affected. Tasks are the card objects of
// the board JSON (`number`, `cardText`, `searchText`, `category`, `updatedAt`).
QtObject {
    id: filter

    property string text: ""
    // Selected category names; a task must be in one of them.
    property var categories: []
    property bool hideOldDone: false
    property int days: 30
    // Clock in ms since the epoch; 0 means the real clock. Tests set it.
    property real now: 0

    readonly property bool active: text.trim() !== "" || categories.length > 0

    function clear() {
        text = ""
        categories = []
    }

    function normalized(s) {
        return (s || "").trim().toLowerCase()
    }

    function hasCategory(name) {
        return categories.some(c => normalized(c) === normalized(name))
    }

    function toggleCategory(name) {
        if (hasCategory(name))
            categories = categories.filter(c => normalized(c) !== normalized(name))
        else
            categories = categories.concat([name])
    }

    // Text and category filters; both must match.
    function matches(task) {
        const q = normalized(text)
        if (q !== "") {
            const digits = q.startsWith("#") ? q.slice(1) : q
            const byNumber = /^\d+$/.test(digits) && String(task.number) === digits
            const haystack = normalized(task.searchText !== undefined ? task.searchText : task.cardText)
            if (!byNumber && !haystack.includes(q))
                return false
        }
        if (categories.length > 0 && !hasCategory(task.category))
            return false
        return true
    }

    // Not changed for `days` days. There is no completion time on a task, so
    // its last update stands in for it. Unknown times are never old.
    function isOld(task) {
        if (!task.updatedAt)
            return false
        const clock = now > 0 ? now : Date.now()
        return clock - task.updatedAt > days * 86400000
    }

    function shows(task, isLastColumn) {
        if (!matches(task))
            return false
        return !(isLastColumn && hideOldDone && isOld(task))
    }

    // The tasks to show, in stored order.
    function visibleTasks(tasks, isLastColumn) {
        return tasks.filter(t => shows(t, isLastColumn))
    }

    // "3 of 14" while something is hidden or filtered, else "14".
    function countText(visible, total) {
        return (active || visible !== total) ? qsTr("%1 of %2").arg(visible).arg(total) : String(total)
    }
}
