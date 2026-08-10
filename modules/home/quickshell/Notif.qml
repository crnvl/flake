import Quickshell.Services.Notifications
import QtQuick

// A single notification, drawn as a box frame:
//
//   ┌─ Signal ─────────────────────────┐
//   │ Alice                            │
//   │ hey, are you around later?       │
//   └──────────────────────────────────┘
//
// Urgency is signalled by frame weight rather than colour -- critical
// notifications get a double-line frame (╔═╗). That's the monochrome
// equivalent of turning the border red, and it's exactly what DOS-era TUIs
// did for modal alerts.
Item {
    id: root

    required property var notif

    readonly property int cols: 46
    // Frame takes 1 cell each side, plus 1 cell of padding each side.
    readonly property int textCols: root.cols - 4

    readonly property bool critical: root.notif.urgency === NotificationUrgency.Critical

    readonly property var summaryLines: Theme.wrap(root.notif.summary, root.textCols)
    readonly property var bodyLines: Theme.wrap(root.notif.body, root.textCols)
    readonly property var lines: root.summaryLines.concat(root.bodyLines)

    // expireTimeout is documented as seconds. Clamped defensively: a client
    // sending milliseconds (or something absurd) can't pin a popup forever.
    readonly property int timeoutMs: {
        if (root.critical)
            return 0;   // critical stays until dismissed
        const t = root.notif.expireTimeout;
        if (t === undefined || t === null || t < 0)
            return 5000;
        if (t === 0)
            return 0;
        return Math.min(t * 1000, 30000);
    }

    implicitWidth: box.implicitWidth
    implicitHeight: box.implicitHeight

    Box {
        id: box

        cols: root.cols
        rowCount: Math.max(1, root.lines.length)
        doubled: root.critical
        title: Theme.clamp(root.notif.appName, root.textCols - 2)
        frameColor: root.critical ? Theme.bright : Theme.dim

        Column {
            x: Theme.cell
            width: Theme.cell * root.textCols
            spacing: 0

            Repeater {
                model: root.lines

                Txt {
                    required property int index
                    required property string modelData

                    width: Theme.cell * root.textCols
                    height: Theme.row
                    text: modelData
                    // Summary at bright intensity, body at normal. Two
                    // intensities is all the hierarchy you need.
                    color: index < root.summaryLines.length ? Theme.bright : Theme.fg
                }
            }
        }
    }

    Timer {
        running: root.timeoutMs > 0
        interval: root.timeoutMs
        onTriggered: root.notif.expire()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton)
                Notifications.dismissAll();
            else
                root.notif.dismiss();
        }
    }
}
