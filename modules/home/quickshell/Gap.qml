import QtQuick

// One character cell of horizontal space. Using this instead of Row.spacing
// keeps every gap on the grid.
Item {
    implicitWidth: Theme.cell
    implicitHeight: Theme.row
}
