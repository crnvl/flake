import QtQuick

// A dim label / normal value pair on the character grid.
Row {
    id: root

    property string label: ""
    property string value: ""
    property int labelCells: 9
    property bool muted: false

    spacing: 0
    height: Theme.row

    Txt {
        text: Theme.padTo(root.label, root.labelCells)
        color: Theme.dim
        height: Theme.row
    }

    Txt {
        text: root.value
        color: root.muted ? Theme.dim : Theme.fg
        height: Theme.row
    }
}
