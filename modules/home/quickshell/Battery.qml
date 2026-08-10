pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Battery straight from sysfs.
//
// Quickshell ships a proper UPower service (Quickshell.Services.UPower) with
// richer data -- charge rate, time-to-empty, health -- but it needs the
// UPower daemon, which this system doesn't run. The old waybar setup read
// sysfs directly too, so this keeps working with no system-level changes.
//
// If you'd rather have the richer data, set `services.upower.enable = true;`
// in modules/nixos/desktop.nix and swap this singleton for UPower.
Singleton {
    id: root

    property real fraction: 0
    property string status: "Unknown"

    readonly property bool charging: root.status === "Charging"
    readonly property bool onBattery: root.status === "Discharging"

    function sample(line) {
        const parts = line.trim().split(/\s+/);
        if (parts.length < 1)
            return;

        const cap = Number(parts[0]);
        if (!isNaN(cap))
            root.fraction = Math.max(0, Math.min(1, cap / 100));
        if (parts.length > 1)
            root.status = parts[1];
    }

    Process {
        id: proc

        running: true
        command: ["sh", "-c", "while :; do cat /sys/class/power_supply/BAT0/capacity /sys/class/power_supply/BAT0/status 2>/dev/null | tr '\\n' ' '; echo; sleep 10; done"]

        onRunningChanged: if (!running)
            retry.start()

        stdout: SplitParser {
            onRead: function (line) {
                root.sample(line);
            }
        }
    }

    Timer {
        id: retry

        interval: 2000
        onTriggered: proc.running = true
    }
}
