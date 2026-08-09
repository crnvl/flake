pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Network state via nmcli.
//
// This is the one thing waybar genuinely did better -- it had a built-in
// `network` module. Quickshell has no NetworkManager service (Astal does),
// so this is a poll. Every 5s is plenty; nothing here changes fast.
Singleton {
    id: root

    property int strength: 0        // 0..100 wifi signal
    property string ssid: ""
    property bool wifi: false
    property bool vpn: false
    property bool connected: false

    function sample(line) {
        const parts = line.split("|");

        // Field 1: the active wifi row from `nmcli device wifi`, e.g. "*:100:vectors"
        const w = parts.length > 0 ? parts[0].trim() : "";
        if (w.length > 0) {
            const f = w.split(":");
            root.strength = Number(f[1]) || 0;
            // SSIDs may contain colons; nmcli escapes them but rejoin anyway.
            root.ssid = f.slice(2).join(":");
            root.wifi = true;
        } else {
            root.wifi = false;
            root.ssid = "";
            root.strength = 0;
        }

        // Field 2: count of active wireguard/vpn connections
        root.vpn = parts.length > 1 && Number(parts[1].trim()) > 0;

        // Field 3: nmcli general state
        root.connected = parts.length > 2 && parts[2].trim().indexOf("connected") === 0;
    }

    Process {
        id: proc

        running: true
        command: ["sh", "-c", `
            while :; do
              w=$(nmcli -t -f IN-USE,SIGNAL,SSID device wifi 2>/dev/null | grep '^[*]' | head -1)
              v=$(nmcli -t -f TYPE connection show --active 2>/dev/null | grep -cE 'wireguard|vpn')
              s=$(nmcli -t -f STATE general 2>/dev/null | head -1)
              echo "$w|$v|$s"
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
