pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// System facts for the desktop dashboard: identity, uptime, memory, disk and
// network throughput.
//
// Split into two processes: one that fires once for things that never change,
// and one 5s loop for everything that does. Everything the loop needs comes
// out of /proc plus a single df, so it's cheap.
Singleton {
    id: root

    // Static
    property string host: ""
    property string kernel: ""
    property string nixos: ""

    // Dynamic
    property real uptime: 0        // seconds
    property real memTotal: 0      // bytes
    property real memUsed: 0
    property real swapTotal: 0
    property real swapUsed: 0
    property real diskTotal: 0
    property real diskUsed: 0
    property real rxRate: 0        // bytes/sec
    property real txRate: 0

    property real lastStamp: 0
    property real lastRx: 0
    property real lastTx: 0

    readonly property real memFrac: root.memTotal > 0 ? root.memUsed / root.memTotal : 0
    readonly property real swapFrac: root.swapTotal > 0 ? root.swapUsed / root.swapTotal : 0
    readonly property real diskFrac: root.diskTotal > 0 ? root.diskUsed / root.diskTotal : 0

    // Binary units, one decimal, no padding. 6148914691 -> "5.7G"
    function fmtBytes(n) {
        if (!n || n < 0)
            return "0B";
        const units = ["B", "K", "M", "G", "T"];
        let v = n;
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (v >= 100 ? v.toFixed(0) : v.toFixed(1)) + units[i];
    }

    function fmtRate(n) {
        return root.fmtBytes(n) + "/s";
    }

    function fmtUptime(s) {
        const d = Math.floor(s / 86400);
        const h = Math.floor((s % 86400) / 3600);
        const m = Math.floor((s % 3600) / 60);
        const hh = h < 10 ? "0" + h : String(h);
        const mm = m < 10 ? "0" + m : String(m);
        return d + "d " + hh + ":" + mm;
    }

    function sampleStatic(line) {
        const f = line.split("|");
        if (f.length < 3)
            return;
        root.host = f[0].trim();
        root.kernel = f[1].trim();
        root.nixos = f[2].trim();
    }

    function sampleDynamic(line) {
        const f = line.trim().split(/\s+/).map(Number);
        if (f.length < 10 || f.some(isNaN))
            return;

        const stamp = f[0];
        root.uptime = f[1];

        const kb = 1024;
        root.memTotal = f[2] * kb;
        root.memUsed = (f[2] - f[3]) * kb;   // total - available
        root.swapTotal = f[4] * kb;
        root.swapUsed = (f[4] - f[5]) * kb;
        root.diskTotal = f[6];
        root.diskUsed = f[7];

        const rx = f[8];
        const tx = f[9];
        if (root.lastStamp > 0 && stamp > root.lastStamp) {
            const dt = stamp - root.lastStamp;
            root.rxRate = Math.max(0, (rx - root.lastRx) / dt);
            root.txRate = Math.max(0, (tx - root.lastTx) / dt);
        }
        root.lastStamp = stamp;
        root.lastRx = rx;
        root.lastTx = tx;
    }

    Process {
        running: true
        command: ["sh", "-c", "printf '%s|%s|%s\\n' \"$(hostname)\" \"$(uname -r)\" \"$(cat /run/current-system/nixos-version 2>/dev/null)\""]

        stdout: SplitParser {
            onRead: function (line) {
                root.sampleStatic(line);
            }
        }
    }

    Process {
        id: proc

        running: true
        command: ["sh", "-c", `
            while :; do
              t=$(date +%s)
              u=$(cut -d' ' -f1 /proc/uptime)
              m=$(awk '/^MemTotal:/{a=$2} /^MemAvailable:/{b=$2} /^SwapTotal:/{c=$2} /^SwapFree:/{d=$2} END{print a, b, c, d}' /proc/meminfo)
              k=$(df -B1 --output=size,used / | tail -1)
              n=$(awk 'NR>2 {gsub(/:/," "); if ($1 != "lo") {rx+=$2; tx+=$10}} END{print rx+0, tx+0}' /proc/net/dev)
              echo "$t $u $m $k $n"
              sleep 5
            done
        `]

        onRunningChanged: if (!running)
            retry.start()

        stdout: SplitParser {
            onRead: function (line) {
                root.sampleDynamic(line);
            }
        }
    }

    Timer {
        id: retry

        interval: 2000
        onTriggered: proc.running = true
    }
}
