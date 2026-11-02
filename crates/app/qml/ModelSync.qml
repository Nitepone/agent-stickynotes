import QtQuick

// Keeps a ListModel in step with an array of items by key, so views built on
// the model add, remove, move and update delegates in place instead of
// rebuilding them all. The model must be created with `dynamicRoles: true` and
// rows are { rowKey, sig, payload }: `sig` is a cheap signature of the item and
// `payload` the item itself (the whole role value is replaced, which is what
// makes delegates notice). An unchanged item is never touched.
QtObject {
    // How many model operations the last sync() performed (for tests).
    property int lastOps: 0

    function signature(item) {
        return JSON.stringify(item)
    }

    function row(item, key) {
        return { rowKey: key, sig: signature(item), payload: item }
    }

    // `keyOf(item)` must be unique within `items`.
    function sync(model, items, keyOf) {
        let ops = 0
        const keys = items.map(keyOf)
        const wanted = {}
        for (const k of keys)
            wanted[k] = true

        for (let i = model.count - 1; i >= 0; i--) {
            if (!wanted[model.get(i).rowKey]) {
                model.remove(i)
                ops++
            }
        }

        for (let i = 0; i < items.length; i++) {
            const key = keys[i]
            if (i < model.count && model.get(i).rowKey === key) {
                const sig = signature(items[i])
                if (model.get(i).sig !== sig) {
                    model.set(i, { rowKey: key, sig: sig, payload: items[i] })
                    ops++
                }
                continue
            }
            let at = -1
            for (let j = i + 1; j < model.count; j++) {
                if (model.get(j).rowKey === key) {
                    at = j
                    break
                }
            }
            if (at >= 0) {
                model.move(at, i, 1)
                ops++
                const sig = signature(items[i])
                if (model.get(i).sig !== sig) {
                    model.set(i, { rowKey: key, sig: sig, payload: items[i] })
                    ops++
                }
            } else {
                model.insert(i, row(items[i], key))
                ops++
            }
        }
        lastOps = ops
    }
}
