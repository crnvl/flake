import QtQuick

// A framed panel drawn with real box-drawing characters rather than borders,
// with an optional inset title:
//
//   ┌─ SYSTEM ─────────┐
//   │                  │
//   └──────────────────┘
//
// Children are placed inside the frame automatically (one cell of inset).
// The bar doesn't use this yet -- it's the primitive for popups, which is
// where box drawing really earns its keep.
Item {
    id: root

    property string title: ""
    property int cols: 24
    property int rowCount: 3
    property bool doubled: false   // ╔═╗ instead of ┌─┐
    property color frameColor: Theme.dim

    default property alias content: inner.data

    readonly property string rendered: {
        const c = root.doubled ? {
            tl: "╔",
            tr: "╗",
            bl: "╚",
            br: "╝",
            h: "═",
            v: "║"
        } : {
            tl: "┌",
            tr: "┐",
            bl: "└",
            br: "┘",
            h: "─",
            v: "│"
        };

        const w = Math.max(4, root.cols);

        let head = c.tl + c.h;
        if (root.title.length > 0)
            head += " " + Theme.clamp(root.title, w - 6) + " ";
        head += c.h.repeat(Math.max(0, w - head.length - 1)) + c.tr;

        const mid = c.v + " ".repeat(w - 2) + c.v;
        const foot = c.bl + c.h.repeat(w - 2) + c.br;

        let lines = [head];
        for (let i = 0; i < Math.max(1, root.rowCount); i++)
            lines.push(mid);
        lines.push(foot);
        return lines.join("\n");
    }

    implicitWidth: Theme.cell * root.cols
    implicitHeight: Theme.row * (root.rowCount + 2)

    Txt {
        anchors.fill: parent
        text: root.rendered
        color: root.frameColor
        // Lock line height to the grid row so the frame's vertical bars line
        // up exactly with the horizontal rules.
        lineHeight: Theme.row
        lineHeightMode: Text.FixedHeight
    }

    Item {
        id: inner

        x: Theme.cell
        y: Theme.row
        width: parent.width - Theme.cell * 2
        height: parent.height - Theme.row * 2
    }
}
