import QtQuick

// Sparkline built from the lower-block elements ▁▂▃▄▅▆▇█.
//
// Braille (⣿) is the other classic option and packs 2x4 dots per cell, but
// it only gives 4 vertical levels in a single-row bar where blocks give 8 --
// and in pure monochrome braille turns to mush at this size. Blocks win here.
// For a taller multi-row panel, braille is the better choice.
Item {
    id: root

    property var values: []   // array of 0.0 .. 1.0, oldest first
    property int cells: 12

    // Floor any non-zero sample to at least ▁ so an idle machine draws a
    // continuous baseline rather than dissolving into blank cells. Without
    // this, anything under ~6% rounds to nothing and the widget reads as
    // broken instead of quiet.
    property bool idleBaseline: true

    readonly property string glyphs: " ▁▂▃▄▅▆▇█"

    readonly property string rendered: {
        const v = root.values;
        const n = root.cells;
        let s = "";
        for (let i = 0; i < n; i++) {
            // Right-align: the newest sample sits at the right edge.
            const idx = v.length - n + i;
            const x = (idx >= 0 && idx < v.length) ? v[idx] : 0;

            let lvl = Math.round(x * 8);
            if (root.idleBaseline && x > 0 && lvl < 1)
                lvl = 1;
            lvl = Math.max(0, Math.min(8, lvl));
            s += root.glyphs.charAt(lvl);
        }
        return s;
    }

    implicitWidth: Theme.cell * root.cells
    implicitHeight: Theme.row

    Txt {
        anchors.fill: parent
        text: root.rendered
    }
}
