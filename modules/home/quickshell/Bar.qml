import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// The bar.
PanelWindow {
    id: bar

    property var modelData

    screen: bar.modelData
    color: Theme.bg

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Theme.barHeight

    // Pipewire nodes are unbound by default; binding the sink is what makes
    // volume/mute readable.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    SystemClock {
        id: clock

        precision: SystemClock.Seconds
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: bar.sink && bar.sink.audio ? bar.sink.audio.volume : 0
    readonly property bool muted: bar.sink && bar.sink.audio ? bar.sink.audio.muted : false

    readonly property bool anyFlag: Status.recording || Status.backupRunning || Status.checkFailed

    // ── Left: workspaces, then the focused window ────────────────────────
    Row {
        id: left

        anchors.left: parent.left
        anchors.leftMargin: Theme.cell
        anchors.top: parent.top
        anchors.topMargin: Theme.padY
        spacing: 0

        Repeater {
            model: Niri.workspacesFor(bar.screen ? bar.screen.name : "")

            Seg {
                required property var modelData

                // Focused workspace gets reverse video. Everything else is
                // dim unless it's active on another output. No colour needed.
                text: modelData.name ? modelData.name : String(modelData.idx)
                reverse: modelData.is_focused || modelData.is_urgent
                muted: !modelData.is_active
            }
        }

        Sep {}

        Seg {
            text: Theme.padTo(Niri.focusedAppId, 14)
            muted: true
        }

        Seg {
            text: Theme.padTo(Niri.focusedTitle, 44)
        }
    }

    // ── Centre: clock ────────────────────────────────────────────────────
    // ISO 8601 because nothing says "terminal" like an unambiguous date.
    Seg {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.padY

        text: Qt.formatDateTime(clock.date, "yyyy-MM-dd ddd hh:mm:ss")
    }

    // ── Right: status flags, network, cpu, volume, battery ───────────────
    Row {
        id: right

        anchors.right: parent.right
        anchors.rightMargin: Theme.cell
        anchors.top: parent.top
        anchors.topMargin: Theme.padY
        spacing: 0

        // Flags only take space when they're active. A Row skips invisible
        // children, so the bar stays tight.
        Seg {
            text: "REC"
            reverse: true
            visible: Status.recording
        }

        Seg {
            text: "BAK"
            visible: Status.backupRunning
        }

        Seg {
            text: "ERR"
            reverse: true
            visible: Status.checkFailed
        }

        Sep {
            visible: bar.anyFlag
        }

        // Network. VPN state gets reverse video -- it's the one piece of
        // information here where being wrong actually matters.
        Seg {
            text: Network.vpn ? "VPN" : "NET"
            reverse: Network.vpn
            muted: !Network.vpn
            padCells: 0
        }

        Gap {}

        Seg {
            text: Theme.padTo(Network.wifi ? Network.ssid : (Network.connected ? "wired" : "offline"), 10)
            muted: !Network.connected
        }

        Sep {}

        Seg {
            // Pending notification count. Reverse video so it reads as an
            // alert without needing colour; hidden entirely when zero.
            visible: Notifications.count > 0
            text: "[" + Notifications.count + "]"
            reverse: true
        }

        Sep {
            visible: Notifications.count > 0
        }

        Seg {
            text: "CPU"
            muted: true
            padCells: 0
        }

        Gap {}

        Spark {
            values: Cpu.history
            cells: 16
        }

        Seg {
            text: Theme.padLeft(Math.round(Cpu.usage * 100) + "%", 4)
        }

        Sep {}

        Seg {
            text: bar.muted ? "MUT" : "VOL"
            muted: true
            padCells: 0
        }

        Gap {}

        Meter {
            value: bar.muted ? 0 : bar.volume
            cells: 8
        }

        Seg {
            text: Theme.padLeft(Math.round(bar.volume * 100) + "%", 4)
        }

        Sep {}

        Seg {
            text: Battery.charging ? "CHG" : (Battery.onBattery ? "BAT" : "AC ")
            muted: true
            padCells: 0
        }

        Gap {}

        Meter {
            value: Battery.fraction
            cells: 8
        }

        Seg {
            // Reverse video as the low-battery alarm -- the monochrome
            // equivalent of turning the widget red.
            text: Theme.padLeft(Math.round(Battery.fraction * 100) + "%", 4)
            reverse: Battery.fraction <= 0.15 && Battery.onBattery
        }
    }

    // ── Bottom rule ──────────────────────────────────────────────────────
    // A row of ─ would be more literally "all characters", but it costs a
    // full grid row of height for a 1px line. This is the one place where a
    // rectangle is the pragmatic call.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.dim
    }
}
