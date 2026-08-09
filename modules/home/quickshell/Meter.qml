import QtQuick

// Horizontal meter drawn with the Unicode left-block elements, which give
// eighth-of-a-cell resolution: a 8-cell meter has 64 distinct states while
// still snapping perfectly to the character grid.
//
// The unfilled track uses ░ (light shade) rather than blank space, because
// in a colourless design you need texture to show the extent of the meter.
Item {
    id: root

    property real value: 0        // 0.0 .. 1.0
    property int cells: 8         // width, in character cells
    property bool track: true

    // U+258F .. U+2589, i.e. 1/8 through 7/8 of a cell filled from the left.
    readonly property string partials: "▏▎▍▌▋▊▉"

    readonly property string rendered: {
        const v = Math.max(0, Math.min(1, root.value));
        const eighths = Math.round(v * root.cells * 8);
        const full = Math.floor(eighths / 8);
        const rem = eighths % 8;

        let s = "█".repeat(full);
        if (rem > 0)
            s += root.partials.charAt(rem - 1);

        const used = full + (rem > 0 ? 1 : 0);
        s += (root.track ? "░" : " ").repeat(Math.max(0, root.cells - used));
        return s;
    }

    implicitWidth: Theme.cell * root.cells
    implicitHeight: Theme.row

    Txt {
        anchors.fill: parent
        text: root.rendered
    }
}
