pragma Singleton

import Quickshell
import QtQuick

// The whole design system: four greys, one font, one cell.
//
// There is deliberately no colour here. On a monochrome terminal you had
// exactly two states -- normal and reverse video -- plus a dim/bright
// intensity bit. Every widget in this config is built from those primitives,
// which is what keeps it feeling like a terminal rather than a bar that
// happens to use a monospace font.
Singleton {
    id: root

    // ── Palette ──────────────────────────────────────────────────────────
    // Not pure black/white: a CRT never was, and pure #000/#fff on an LCD
    // reads as harsh rather than old.
    readonly property color bg: "#0b0b0b"      // background
    readonly property color fg: "#c9c9c9"      // normal intensity
    readonly property color dim: "#5e5e5e"     // dim intensity (chrome, tracks)
    readonly property color bright: "#f4f4f4"  // bright intensity (emphasis)

    // ── Font ─────────────────────────────────────────────────────────────
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 14

    readonly property FontMetrics fm: FontMetrics {
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
    }

    // ── The grid ─────────────────────────────────────────────────────────
    // This is the entire point of doing this in QML. `cell` and `row` are
    // measured from the font at runtime, so every widget sizes itself in
    // character cells. Change fontSize above and the whole shell re-lays
    // itself out on the new grid, still perfectly aligned.
    readonly property real cell: Math.max(1, root.fm.advanceWidth("0"))
    readonly property real row: Math.max(1, Math.ceil(root.fm.height))

    // Vertical padding above/below the content row, in pixels.
    readonly property int padY: 4

    // Single source of truth for the bar's height, so popups can position
    // themselves directly beneath it.
    readonly property int barHeight: root.row + root.padY * 2 + 1

    function cols(n) {
        return Math.round(n * root.cell);
    }

    function rows(n) {
        return Math.round(n * root.row);
    }

    // Truncate to a fixed number of cells so text can never break the grid.
    function clamp(s, n) {
        if (n <= 0)
            return "";
        if (s.length <= n)
            return s;
        return s.slice(0, n - 1) + "…";
    }

    // Pad to exactly n cells so segments never resize as their value changes
    // (a jittering bar is the fastest way to lose the TUI illusion).
    function padTo(s, n) {
        if (s.length >= n)
            return root.clamp(s, n);
        return s + " ".repeat(n - s.length);
    }

    function padLeft(s, n) {
        if (s.length >= n)
            return root.clamp(s, n);
        return " ".repeat(n - s.length) + s;
    }

    // Greedy word wrap to a fixed column count, hard-breaking any word too
    // long to ever fit. Returns an array of lines, none exceeding `cols`.
    // Text on a character grid has to be wrapped by us -- letting Text do it
    // would break cell alignment.
    function wrap(text, cols) {
        if (!text || cols <= 0)
            return [];

        const words = text.split(/\s+/).filter(function (w) {
            return w.length > 0;
        });

        let lines = [];
        let cur = "";
        for (let i = 0; i < words.length; i++) {
            const w = words[i];
            if (cur.length === 0)
                cur = w;
            else if (cur.length + 1 + w.length <= cols)
                cur += " " + w;
            else {
                lines.push(cur);
                cur = w;
            }
        }
        if (cur.length > 0)
            lines.push(cur);

        let out = [];
        for (let j = 0; j < lines.length; j++) {
            const l = lines[j];
            if (l.length <= cols)
                out.push(l);
            else
                for (let k = 0; k < l.length; k += cols)
                    out.push(l.slice(k, k + cols));
        }
        return out;
    }
}
