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
    // Text on a note: the usual dark tones, moved only as far as needed to
    // stay legible (WCAG AA) on whatever color the user picked.
    readonly property color noteText: legibleOn("#2b2813", note, 4.5)
    readonly property color noteNumber: legibleOn("#5e5a3f", note, 4.5)    // gray, quieter than the text
    readonly property color noteSubtleText: legibleOn("#4d4a33", note, 4.5)
    readonly property color noteDoneText: legibleOn("#166534", note, 4.5)
    readonly property color noteHoverBorder: mix(note, noteText, 0.35)
    readonly property color noteShadow: dark ? "#66000000" : "#33000000"
    readonly property color progressTrack: "#26000000"
    readonly property color progressDone: "#16a34a"

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

    // ---- Layout constants (not colors, but shared by every view) ----------

    readonly property int columnWidth: 284
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
