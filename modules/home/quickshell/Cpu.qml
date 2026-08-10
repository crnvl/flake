pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// CPU utilisation from /proc/stat: an aggregate figure plus a short history
// for the bar's sparkline, and per-core figures for the desktop dashboard.
//
// One awk invocation flattens every cpu line into a single delimited record,
// so the whole thing stays one process and one parse regardless of core count.
Singleton {
    id: root

    property real usage: 0
    property var history: []
    property var cores: []

    property var prev: ({})

    readonly property int historyLength: 48

    function sample(line) {
        const entries = line.split(";").filter(function (e) {
            return e.length > 0;
        });
        if (entries.length === 0)
            return;

        const next = {};
        const nextCores = [];
        let agg = -1;

        for (let i = 0; i < entries.length; i++) {
            const f = entries[i].split(",");
            if (f.length < 5)
                continue;

            const name = f[0];
            const total = Number(f[1]) + Number(f[2]) + Number(f[3]) + Number(f[4]);
            const idle = Number(f[4]);
            if (isNaN(total) || isNaN(idle))
                continue;

            next[name] = {
                total: total,
                idle: idle
            };

            const p = root.prev[name];
            let u = 0;
            if (p) {
                const dTotal = total - p.total;
                const dIdle = idle - p.idle;
                u = dTotal > 0 ? Math.max(0, Math.min(1, 1 - dIdle / dTotal)) : 0;
            }

            if (name === "cpu")
                agg = p ? u : -1;
            else
                nextCores.push(u);
        }

        root.prev = next;
        if (nextCores.length > 0)
            root.cores = nextCores;

        // Only start recording once we have a delta to compare against,
        // otherwise the first sample lands as a bogus 0.
        if (agg >= 0) {
            root.usage = agg;
            const h = root.history.slice();
            h.push(agg);
            while (h.length > root.historyLength)
                h.shift();
            root.history = h;
        }
    }

    Process {
        id: proc

        running: true
        command: ["sh", "-c", "while :; do awk '/^cpu/ {printf \"%s,%s,%s,%s,%s;\", $1, $2, $3, $4, $5} END {print \"\"}' /proc/stat; sleep 2; done"]

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
