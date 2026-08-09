pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Backlight level from sysfs. Polled rather than event-driven because the
// kernel gives us no change notification here.
//
// A cleaner future option: Quickshell's IpcHandler, so the niri brightness
// keybind pushes the value in directly instead of us polling for it.
Singleton {
    id: root

    property real fraction: 0
    property bool ready: false

    function sample(line) {
        const p = line.trim().split(/\s+/).map(Number);
        if (p.length < 2 || isNaN(p[0]) || isNaN(p[1]) || p[1] <= 0)
            return;

        root.fraction = Math.max(0, Math.min(1, p[0] / p[1]));
        root.ready = true;
    }

    Process {
        id: proc

        running: true
        // `set --` picks the first backlight device without hardcoding
        // intel_backlight, so this survives a hardware change.
        command: ["sh", "-c", "set -- /sys/class/backlight/*; d=$1; while :; do cat $d/brightness $d/max_brightness 2>/dev/null | tr '\\n' ' '; echo; sleep 0.5; done"]

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
