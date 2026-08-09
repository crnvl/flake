pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// CPU utilisation sampled from /proc/stat, kept as a short history so the
// sparkline has something to draw.
//
// A shell loop feeding a pipe is used rather than a QML timer + file read
// because it keeps the sampling interval honest even if the UI thread is
// busy -- and it's one process for the lifetime of the shell, not one per tick.
Singleton {
    id: root

    property real usage: 0
    property var history: []

    property real lastTotal: 0
    property real lastIdle: 0

    readonly property int historyLength: 32

    function sample(line) {
        const parts = line.trim().split(/\s+/).map(Number);
        if (parts.length < 4 || parts.some(isNaN))
            return;

        const idle = parts[3];
        const total = parts[0] + parts[1] + parts[2] + parts[3];

        if (root.lastTotal > 0) {
            const dTotal = total - root.lastTotal;
            const dIdle = idle - root.lastIdle;
            const u = dTotal > 0 ? (1 - dIdle / dTotal) : 0;
            root.usage = Math.max(0, Math.min(1, u));

            const h = root.history.slice();
            h.push(root.usage);
            while (h.length > root.historyLength)
                h.shift();
            root.history = h;
        }

        root.lastTotal = total;
        root.lastIdle = idle;
    }

    Process {
        id: proc

        running: true
        command: ["sh", "-c", "while :; do read -r _ u n s i rest < /proc/stat; echo \"$u $n $s $i\"; sleep 2; done"]

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

        interval: 1000
        onTriggered: proc.running = true
    }
}
