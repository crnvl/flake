import QtQuick

// A bar segment. Emphasis is reverse video, not colour -- swap foreground
// and background, exactly like a monochrome terminal highlighting a
// selection. `muted` is the dim intensity bit.
Item {
    id: root

    property string text: ""
    property bool reverse: false
    property bool muted: false
    property int padCells: 1

    readonly property color fgColor: root.reverse ? Theme.bg : (root.muted ? Theme.dim : Theme.fg)
    readonly property color bgColor: root.reverse ? Theme.fg : "transparent"

    implicitWidth: label.implicitWidth + Theme.cell * root.padCells * 2
    implicitHeight: Theme.row

    Rectangle {
        anchors.fill: parent
        color: root.bgColor
    }

    Txt {
        id: label

        anchors.centerIn: parent
        text: root.text
        color: root.fgColor
    }
}
