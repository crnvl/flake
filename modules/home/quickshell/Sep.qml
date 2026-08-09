import QtQuick

// Vertical rule between bar segments, drawn as an actual box-drawing
// character so it aligns to the grid and matches Box.qml's frames.
Item {
    implicitWidth: Theme.cell * 3
    implicitHeight: Theme.row

    Txt {
        anchors.centerIn: parent
        text: "│"
        color: Theme.dim
    }
}
