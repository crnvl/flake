import QtQuick

// Seven-segment style clock. Each glyph is a 3x5 bitmap.
//
// Originally drawn with █ characters, but the full-block glyph doesn't occupy
// the entire line box -- JetBrains Mono leaves leading above and below it, so
// stacked rows rendered as disconnected chunks with visible seams. Trying to
// close the gap by fudging lineHeight is fragile and font-specific.
//
// A bitmap is a bitmap, so it's drawn as one: each lit cell is a rectangle
// sized to an exact multiple of the base grid. Tiles seamlessly, stays on the
// grid, and no longer depends on how a particular font rasterises U+2588.
Item {
    id: root

    property string time: "00:00"
    property color glyphColor: Theme.fg

    // One bitmap cell, in base grid units.
    property real pixelW: Math.round(Theme.cell * 3)
    property real pixelH: Math.round(Theme.row * 1.5)

    readonly property var glyphs: ({
            "0": ["███", "█ █", "█ █", "█ █", "███"],
            "1": ["  █", "  █", "  █", "  █", "  █"],
            "2": ["███", "  █", "███", "█  ", "███"],
            "3": ["███", "  █", "███", "  █", "███"],
            "4": ["█ █", "█ █", "███", "  █", "  █"],
            "5": ["███", "█  ", "███", "  █", "███"],
            "6": ["███", "█  ", "███", "█ █", "███"],
            "7": ["███", "  █", "  █", "  █", "  █"],
            "8": ["███", "█ █", "███", "█ █", "███"],
            "9": ["███", "█ █", "███", "  █", "███"],
            ":": ["   ", " █ ", "   ", " █ ", "   "],
            " ": ["   ", "   ", "   ", "   ", "   "]
        })

    // Flattened list of lit cells: [{ x, y }, ...] in bitmap coordinates.
    readonly property var lit: {
        let out = [];
        for (let i = 0; i < root.time.length; i++) {
            const g = root.glyphs[root.time.charAt(i)];
            if (!g)
                continue;
            const ox = i * 4;   // 3 wide + 1 gap
            for (let r = 0; r < 5; r++)
                for (let c = 0; c < 3; c++)
                    if (g[r].charAt(c) === "█")
                        out.push({
                            x: ox + c,
                            y: r
                        });
        }
        return out;
    }

    readonly property int widthCells: Math.max(0, root.time.length * 4 - 1)

    implicitWidth: root.pixelW * root.widthCells
    implicitHeight: root.pixelH * 5

    Repeater {
        model: root.lit

        Rectangle {
            required property var modelData

            x: modelData.x * root.pixelW
            y: modelData.y * root.pixelH
            width: root.pixelW
            height: root.pixelH
            color: root.glyphColor
        }
    }
}
