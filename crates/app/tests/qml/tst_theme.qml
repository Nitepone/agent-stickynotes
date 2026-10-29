import QtQuick
import QtTest
import StickyNotes

TestCase {
    name: "Theme"

    function cleanup() {
        Theme.mode = "light"
        Theme.primaryColor = ""
        Theme.secondaryColor = ""
    }

    function same(a, b, message) {
        compare(Qt.color(a).toString(), Qt.color(b).toString(), message)
    }

    // ---- modes -----------------------------------------------------------

    function test_light_is_the_default() {
        compare(Theme.mode, "light")
        verify(!Theme.dark)
        compare(Theme.primaryColor, "")
        compare(Theme.secondaryColor, "")
    }

    function test_switching_mode_changes_the_whole_palette() {
        const tokens = ["background", "surface", "columnBackground", "text", "subtleText",
                        "fieldBackground", "fieldBorder", "controlBackground", "note",
                        "warning", "danger", "success", "bannerBackground", "primary", "secondary"]
        const light = {}
        for (const t of tokens) light[t] = Theme[t].toString()
        Theme.mode = "dark"
        verify(Theme.dark)
        for (const t of tokens)
            verify(Theme[t].toString() !== light[t], t + " should differ between light and dark")
        // Dark surfaces are dark, light surfaces are light.
        verify(Theme.luminance(Theme.background) < 0.1)
        Theme.mode = "light"
        verify(Theme.luminance(Theme.background) > 0.5)
    }

    // ---- custom colors ---------------------------------------------------

    function test_custom_primary_drives_primary_accents() {
        Theme.primaryColor = "#ff8800"
        same(Theme.primary, "#ff8800")
        same(Theme.dropIndicator, "#ff8800", "drop indicators follow the primary color")
        // Text on the accent stays readable whatever was chosen.
        verify(Theme.contrast(Theme.primary, Theme.textOnPrimary) >= 4.5)
    }

    function test_custom_secondary_drives_secondary_accents() {
        const before = Theme.columnEditBackground.toString()
        Theme.secondaryColor = "#00aa99"
        same(Theme.secondary, "#00aa99")
        verify(Theme.columnEditBackground.toString() !== before, "edit-mode tint follows secondary")
        verify(Theme.contrast(Theme.secondary, Theme.textOnSecondary) >= 4.5)
    }

    function test_links_stay_legible_for_any_secondary_color() {
        for (const mode of ["light", "dark"]) {
            Theme.mode = mode
            for (const color of ["#ffff00", "#00ffff", "#000000", "#ffffff", "#ff00ff", "#7f7f7f"]) {
                Theme.secondaryColor = color
                for (const bg of [Theme.surface, Theme.background, Theme.columnEditBackground])
                    verify(Theme.contrast(Theme.link, bg) >= 4.5,
                           color + " in " + mode + " mode gives link contrast " + Theme.contrast(Theme.link, bg))
            }
        }
    }

    function test_default_colors_depend_on_the_mode() {
        const lightPrimary = Theme.primary.toString()
        Theme.mode = "dark"
        verify(Theme.primary.toString() !== lightPrimary)
        same(Theme.primary, Theme.defaultPrimary)
        same(Theme.secondary, Theme.defaultSecondary)
    }

    function test_invalid_colors_fall_back_to_the_default() {
        for (const bad of ["red", "#12345", "#gggggg", "2563eb", "  "]) {
            Theme.primaryColor = bad
            Theme.secondaryColor = bad
            same(Theme.primary, Theme.defaultPrimary, "primary for " + JSON.stringify(bad))
            same(Theme.secondary, Theme.defaultSecondary, "secondary for " + JSON.stringify(bad))
        }
    }

    function test_resetting_restores_the_defaults_of_the_current_mode() {
        Theme.mode = "dark"
        Theme.primaryColor = "#ff8800"
        Theme.secondaryColor = "#00aa99"
        Theme.primaryColor = ""
        Theme.secondaryColor = ""
        same(Theme.primary, "#60a5fa")
        same(Theme.secondary, "#a5b4fc")
        Theme.mode = "light"
        same(Theme.primary, "#2563eb")
        same(Theme.secondary, "#4f46e5")
    }

    // ---- WCAG AA contrast with the default colors ------------------------

    // [foreground, background] token pairs that carry text (4.5:1 for body text).
    readonly property var textPairs: [
        ["text", "background"], ["text", "surface"], ["text", "columnBackground"],
        ["text", "columnEditBackground"], ["text", "fieldBackground"], ["text", "controlBackground"],
        ["subtleText", "background"], ["subtleText", "surface"], ["subtleText", "columnBackground"],
        ["subtleText", "fieldBackground"],
        ["noteText", "note"], ["noteNumber", "note"], ["noteSubtleText", "note"], ["noteDoneText", "note"],
        ["warning", "surface"], ["danger", "surface"], ["success", "surface"],
        ["text", "bannerBackground"], ["warning", "bannerBackground"],
        ["link", "surface"], ["link", "background"], ["link", "columnEditBackground"],
        ["textOnPrimary", "primary"], ["textOnSecondary", "secondary"], ["textOnDanger", "danger"],
        ["textOnStatus", "agentReadOnly"], ["textOnStatus", "agentReadWrite"],
        ["danger", "fieldBackground"],
    ]

    function test_default_colors_meet_wcag_aa_in_both_modes() {
        const failures = []
        for (const mode of ["light", "dark"]) {
            Theme.mode = mode
            for (const [fg, bg] of textPairs) {
                const ratio = Theme.contrast(Theme[fg], Theme[bg])
                if (ratio < 4.5)
                    failures.push(mode + ": " + fg + " on " + bg + " = " + ratio.toFixed(2))
            }
        }
        compare(failures, [], "pairs below 4.5:1")
    }

    function test_contrast_function_matches_known_values() {
        compare(Theme.contrast("#000000", "#ffffff").toFixed(1), "21.0")
        compare(Theme.contrast("#ffffff", "#ffffff").toFixed(1), "1.0")
        // The WCAG reference gray #767676 on white is the classic 4.5:1 case.
        verify(Math.abs(Theme.contrast("#767676", "#ffffff") - 4.54) < 0.05)
    }

    function test_readable_text_color_is_chosen_for_any_accent() {
        for (const c of ["#000000", "#ffffff", "#ffff00", "#0000ff", "#808080", "#ff0000"])
            verify(Theme.contrast(c, Theme.readableOn(c)) >= 4.5, c)
    }
}
