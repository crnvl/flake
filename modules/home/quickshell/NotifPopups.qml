import Quickshell
import QtQuick

// Popup stack, top-right, tucked directly under the bar.
//
// The window sizes itself exactly to its contents and hides entirely when
// empty, so there's no invisible rectangle swallowing clicks -- no input
// mask needed.
PanelWindow {
    id: popups

    property var modelData

    screen: popups.modelData
    color: "transparent"
    visible: Notifications.list.length > 0

    anchors {
        top: true
        right: true
    }

    // Never reserve screen space; notifications float over windows.
    exclusionMode: ExclusionMode.Ignore

    margins {
        top: Theme.barHeight + Theme.padY
        right: Theme.cell
    }

    implicitWidth: column.implicitWidth
    implicitHeight: Math.max(1, column.implicitHeight)

    Column {
        id: column

        spacing: Theme.padY

        Repeater {
            model: Notifications.list

            Notif {
                required property var modelData

                notif: modelData
            }
        }
    }
}
