pragma Singleton
import QtQuick

// The only place colors are defined. Views use these tokens and never
// hard-code a color, so switching mode or accent colors restyles everything.
//
// The app sets `mode`, `primaryColor` and `secondaryColor` from the user's
// settings; everything else is derived from them.
QtObject {
    id: theme

    // ---- User choices ----------------------------------------------------

    property string mode: "light"       // "light" or "dark"
    property string primaryColor: ""    // "#rrggbb", or "" for the mode's default
    property string secondaryColor: ""  // "#rrggbb", or "" for the mode's default
    property string noteColor: ""       // "#rrggbb", or "" for the yellow note
    property string noteStyle: "user"   // "user": one note color; "variable": a color per category
    property string notePalette: ""     // id of a notePalettes entry ("" is the first)
    property var noteCategories: []     // the board's categories (see categoryColors)

    readonly property bool dark: mode === "dark"

    // ---- Accents ---------------------------------------------------------

    readonly property color defaultPrimary: dark ? "#60a5fa" : "#2563eb"
    readonly property color defaultSecondary: dark ? "#a5b4fc" : "#4f46e5"

    // Primary: interactive and active things (default buttons, drop
    // indicators, progress, focus, selection).
    readonly property color primary: isHexColor(primaryColor) ? Qt.color(primaryColor) : defaultPrimary
    // Secondary: supporting accents (links, column edit mode, add-column).
    readonly property color secondary: isHexColor(secondaryColor) ? Qt.color(secondaryColor) : defaultSecondary

    // Readable text on top of an accent fill, whatever color the user picked.
    readonly property color textOnPrimary: readableOn(primary)
    readonly property color textOnSecondary: readableOn(secondary)
    // Secondary as text (links): nudged only as far as needed to stay legible
    // on every surface a link can appear on.
    readonly property color link: ensureContrast(
        secondary, [surface, background, columnBackground, columnEditBackground], 4.5)

    // Ready-made accent colors offered in preferences.
    readonly property var accentPresets: [
        "#2563eb", "#0284c7", "#0d9488", "#16a34a", "#ca8a04",
        "#ea580c", "#dc2626", "#db2777", "#7c3aed", "#475569"
    ]

    // ---- Surfaces and text ----------------------------------------------

    readonly property color background: dark ? "#14171c" : "#e9edf2"
    readonly property color surface: dark ? "#1f242c" : "#f0f0f0"
    readonly property color columnBackground: dark ? "#222831" : "#dde2ea"
    readonly property color columnEditBackground: mix(columnBackground, secondary, dark ? 0.28 : 0.22)
    readonly property color text: dark ? "#e5e7eb" : "#1f2937"
    readonly property color subtleText: dark ? "#a3abb8" : "#4b5563"

    readonly property color fieldBackground: dark ? "#2b313b" : "#ffffff"
    readonly property color fieldBorder: dark ? "#4a5361" : "#a4acb8"
    readonly property color controlBackground: dark ? "#2c333d" : "#e6e9ee"
    readonly property color controlHover: dark ? "#363e4a" : "#cdd3dd"
    readonly property color controlDown: dark ? "#424c5a" : "#bcc4d1"

    // Shading roles of the standard controls' palette (bevels, outlines,
    // scroll bar handles and tracks). Main.qml applies them on Windows only,
    // where the system palette would otherwise leak into them in dark mode.
    readonly property color shadeLight: dark ? "#4a5361" : "#ffffff"
    readonly property color shadeMidlight: dark ? "#3b4350" : "#f3f5f8"
    readonly property color shadeMid: dark ? "#363e4a" : "#c4cad4"
    readonly property color shadeDark: dark ? "#14171c" : "#9aa2ae"
    readonly property color shadeShadow: dark ? "#0b0d10" : "#6b7280"

    // ---- Sticky notes (a note keeps its color in both modes) ---------------

    readonly property color defaultNote: dark ? "#e8d572" : "#fff1a6"
    readonly property color note: isHexColor(noteColor) ? Qt.color(noteColor) : defaultNote
    // Ready-made note colors offered in preferences.
    readonly property var notePresets: [
        "#fff1a6", "#ffd8a8", "#ffc2d4", "#e2c9ff",
        "#bfe3ff", "#b9ecd0", "#d4efa6", "#e5e7eb"
    ]

    // ---- Variable note colors: one palette color per category --------------
    // Each palette is ordered so that neighbours are far apart in hue: the
    // first colors handed out look as different as possible. Palette colors
    // are the same in both modes, like the user's own note color.

    readonly property var notePalettes: [
        { id: "pastel", name: qsTr("Pastel"), colors: [
            "#faeda8", "#a8f1fa", "#faa8d9", "#c2faa8", "#a8abfa", "#fabca8",
            "#a8fad4", "#eba8fa", "#f2faa8", "#a8dbfa", "#faa8c3", "#acfaa8"] },
        { id: "soft-earth", name: qsTr("Soft earth"), colors: [
            "#dac6a9", "#a9dad4", "#daa9d3", "#c5daa9", "#a9b7da", "#daa9a9",
            "#a9dab7", "#c5a9da", "#dad3a9", "#a9d4da", "#daa9c6", "#b8daa9"] },
        { id: "candy", name: qsTr("Candy"), colors: [
            "#ffb2d9", "#c3ffb2", "#b8b2ff", "#ffcdb2", "#b2ffe3", "#f9b2ff",
            "#f0ffb2", "#b2daff", "#ffb2c4", "#b2ffb6", "#ccb2ff", "#ffe2b2"] },
        { id: "cool", name: qsTr("Cool"), colors: [
            "#aff4c6", "#f7c9f7", "#afc6f4", "#c9f7f7", "#c6aff4", "#c9f7e8",
            "#afddf4", "#c9c9f7", "#ddaff4", "#c9f7e0", "#aff4e8", "#c9f0f7"] }
    ]
    readonly property var activeNotePalette: paletteById(notePalette)
    readonly property bool variableNotes: noteStyle === "variable"
    // { normalized category: "#rrggbb" } for the categories on the board.
    readonly property var categoryColors: assignCategoryColors(noteCategories, activeNotePalette.colors)

    function paletteById(id) {
        for (const p of notePalettes)
            if (p.id === id)
                return p
        return notePalettes[0]
    }

    // Case and surrounding spaces do not make a different category.
    function normalizeCategory(category) {
        return (category || "").trim().toLowerCase()
    }

    // Gives each distinct category (ignoring case) a palette color: sort the
    // names, then take the palette in order, wrapping when there are more
    // categories than colors. Depends only on the set of categories, never on
    // the order they were created in or listed.
    function assignCategoryColors(categories, colors) {
        const names = []
        for (const c of categories || []) {
            const n = normalizeCategory(c)
            if (n !== "" && names.indexOf(n) < 0)
                names.push(n)
        }
        names.sort((a, b) => a < b ? -1 : a > b ? 1 : 0)
        const result = {}
        names.forEach((n, i) => { result[n] = colors[i % colors.length] })
        return result
    }

    // The color of a note in `category`: the palette color when notes vary by
    // category, otherwise (and for uncategorized notes) the user's note color.
    function noteColorFor(category) {
        if (!variableNotes)
            return note
        const c = categoryColors[normalizeCategory(category)]
        return c ? Qt.color(c) : note
    }

    // Text on a note: the usual dark tones, moved only as far as needed to
    // stay legible (WCAG AA) on whatever color the note has.
    function noteTextOn(bg) { return legibleOn("#2b2813", bg, 4.5) }
    function noteNumberOn(bg) { return legibleOn("#5e5a3f", bg, 4.5) }    // gray, quieter than the text
    function noteSubtleTextOn(bg) { return legibleOn("#4d4a33", bg, 4.5) }
    function noteDoneTextOn(bg) { return legibleOn("#166534", bg, 4.5) }
    function noteHoverBorderOn(bg) { return mix(bg, noteTextOn(bg), 0.35) }
    function noteChipOn(bg) { return mix(bg, noteTextOn(bg), 0.12) }
    function noteChipTextOn(bg) { return legibleOn(noteTextOn(bg), noteChipOn(bg), 4.5) }

    readonly property color noteText: noteTextOn(note)
    readonly property color noteNumber: noteNumberOn(note)
    readonly property color noteSubtleText: noteSubtleTextOn(note)
    readonly property color noteDoneText: noteDoneTextOn(note)
    readonly property color noteHoverBorder: noteHoverBorderOn(note)
    readonly property color noteShadow: dark ? "#66000000" : "#33000000"
    readonly property color progressTrack: "#26000000"
    readonly property color progressDone: "#16a34a"

    // Category label on a note, and the header of a stack of notes in a column.
    readonly property color noteChip: noteChipOn(note)
    readonly property color noteChipText: noteChipTextOn(note)
    readonly property color stackHeaderBackground: mix(columnBackground, text, dark ? 0.14 : 0.1)
    readonly property color stackHeaderCount: legibleOn(subtleText, stackHeaderBackground, 4.5)

    // ---- Notes an agent changed -------------------------------------------
    // The glow is green for now; this is the one place to change it (or to
    // derive it from a theme later).

    readonly property color glow: "#22c55e"
    readonly property color glowCore: "#bbf7d0"        // the bright head of the moving highlight
    readonly property color sheen: "#66ffffff"         // the band that sweeps across an edited note
    readonly property int glowRotationMs: 3000         // one trip around the note
    readonly property int glowSheenMs: 2400            // one sweep across the note
    readonly property int glowFadeMs: 20000            // fade after the user is back

    // ---- Status ----------------------------------------------------------

    readonly property color warning: dark ? "#fbbf24" : "#a84a08"
    readonly property color danger: dark ? "#f87171" : "#b91c1c"
    readonly property color textOnDanger: readableOn(danger)
    readonly property color success: dark ? "#4ade80" : "#136f34"
    readonly property color bannerBackground: dark ? "#3a2f12" : "#fef3c7"
    readonly property color agentReadWrite: "#15803d"        // agents may write: green
    readonly property color agentReadOnly: "#facc15"         // agents may only read: yellow
    readonly property color textOnAgentReadWrite: "#ffffff"
    readonly property color textOnAgentReadOnly: "#1f2937"

    // Where things are dropped.
    readonly property color dropIndicator: primary

    // Keyboard focus ring: the primary color, nudged until it reaches 3:1
    // (WCAG non-text contrast) on every surface a focusable item sits on.
    readonly property color focusRing: ensureContrast(
        primary, [background, surface, columnBackground, columnEditBackground], 3)

    // ---- Layout constants (not colors, but shared by every view) ----------

    readonly property int columnWidth: 284
    readonly property int collapsedColumnWidth: 48
    readonly property int columnSpacing: 12
    readonly property int cardSpacing: 8
    readonly property int radius: 8
    readonly property int suggestedDescriptionChars: 200

    // ---- Color helpers ----------------------------------------------------

    function isHexColor(value) {
        return typeof value === "string" && /^#[0-9a-fA-F]{6}$/.test(value)
    }

    function sameColor(a, b) {
        return Qt.color(a).toString() === Qt.color(b).toString()
    }

    function mix(a, b, amount) {
        return Qt.rgba(a.r * (1 - amount) + b.r * amount,
                       a.g * (1 - amount) + b.g * amount,
                       a.b * (1 - amount) + b.b * amount, 1)
    }

    function channel(c) {
        return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    }

    // WCAG relative luminance and contrast ratio (1 to 21).
    function luminance(color) {
        const c = Qt.color(color)
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    function contrast(a, b) {
        const la = luminance(a)
        const lb = luminance(b)
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }

    // White or black, whichever reads better on `background`. One of the two
    // always reaches 4.5:1, whatever the background.
    function readableOn(background) {
        return contrast(background, "#ffffff") >= contrast(background, "#000000")
               ? Qt.color("#ffffff") : Qt.color("#000000")
    }

    // `color`, moved toward black or white (whichever contrasts more with
    // `background`) until it reaches `ratio` against it. Unchanged if it already does.
    function legibleOn(color, background, ratio) {
        let c = Qt.color(color)
        const towards = contrast("#000000", background) >= contrast("#ffffff", background)
                        ? Qt.color("#000000") : Qt.color("#ffffff")
        for (let i = 0; i < 30 && contrast(c, background) < ratio; i++)
            c = mix(c, towards, 0.1)
        return c
    }

    // `color`, moved toward white (dark mode) or black (light mode) until it
    // reaches `ratio` against every color in `backgrounds`. Unchanged if it
    // already does.
    function ensureContrast(color, backgrounds, ratio) {
        let c = Qt.color(color)
        const towards = dark ? Qt.color("#ffffff") : Qt.color("#000000")
        const worst = () => Math.min(...backgrounds.map(b => contrast(c, b)))
        for (let i = 0; i < 30 && worst() < ratio; i++)
            c = mix(c, towards, 0.1)
        return c
    }
}
