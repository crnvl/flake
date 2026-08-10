pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The three shell-polled indicators carried over from waybar's custom/*
// modules: screen recording, running backup, failed backup check.
//
// These were shell-outs in waybar and they're still shell-outs here -- there
// was never a win available. The difference is one 5s loop for all three
// instead of three independent waybar intervals (1s, 5s, 30s).
Singleton {
    id: root

    property bool recording: false
    property bool backupRunning: false
    property bool checkFailed: false

    function sample(line) {
        const f = line.trim().split(/\s+/);
        if (f.length < 3)
            return;

        root.recording = f[0] === "1";
        root.backupRunning = f[1] === "1";
        root.checkFailed = f[2] === "1";
    }

    Process {
        id: proc

        running: true
        command: ["sh", "-c", `
            while :; do
              r=0
              p="$XDG_RUNTIME_DIR/niri-record.pid"
              if [ -f "$p" ] && kill -0 "$(cat "$p")" 2>/dev/null; then r=1; fi

              b=0
              systemctl is-active --quiet borgbackup-job-home.service && b=1

              c=0
              systemctl is-failed --quiet borgbackup-check-home.service && c=1

              echo "$r $b $c"
              sleep 5
            done
        `]

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
