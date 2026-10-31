pragma Singleton
import QtQuick

// Shared helpers for the QML view tests. Staged by scripts/qml-tests.sh as the
// separate `TestSupport` module; it is not part of the app's StickyNotes module.
QtObject {
    // Every item under `root` (pre-order, children only; with `includeData`, also
    // non-item objects in `data`) for which `predicate(item)` is true.
    function findWhere(root, predicate, includeData) {
        const found = []
        ;(function walk(item) {
            for (const child of item.children) {
                if (predicate(child)) found.push(child)
                walk(child)
            }
            if (includeData)
                for (const child of item.data)
                    if (predicate(child) && found.indexOf(child) < 0) found.push(child)
        })(root)
        return found
    }

    // Every object named `name` under `root`.
    function findAllByName(root, name, includeData) {
        return findWhere(root, c => c.objectName === name, includeData)
    }

    // The last (deepest, latest) item named `name` under `root`, or null.
    function findByName(root, name) {
        const found = findAllByName(root, name)
        return found.length ? found[found.length - 1] : null
    }

    // The sample three-column board shared by the board and keyboard tests.
    // Options: firstDescription (column one's description), artifactCount (on
    // task #2), doing (put a task in the middle column).
    function sampleBoard(opts) {
        const o = opts || {}
        return {
            title: "Test",
            columns: [
                { id: "c0", title: "Backlog", description: o.firstDescription || "", tasks: [
                    { id: "t0", number: 1, cardText: "first", done: 0, total: 0 },
                    Object.assign({ id: "t1", number: 2, cardText: "second", done: 1, total: 2 },
                                  o.artifactCount ? { artifactCount: o.artifactCount } : {}),
                ] },
                { id: "c1", title: "Doing", description: "", tasks: o.doing ? [
                    { id: "t3", number: 4, cardText: "fourth", done: 0, total: 0 },
                ] : [] },
                { id: "c2", title: "Done", description: "", tasks: [
                    { id: "t2", number: 12, cardText: "third", done: 2, total: 2 },
                ] },
            ],
        }
    }
}
