pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Niri IPC. Neither Quickshell nor Astal ships a niri integration (both have
// Hyprland; Quickshell adds I3, Astal adds River), so this is the piece you
// hand-roll on any framework other than waybar.
//
// It is genuinely not much: niri emits newline-delimited JSON where every
// event is a single-key object, e.g.
//   {"WorkspaceActivated":{"id":6,"focused":true}}
//
// The stream sends a full WorkspacesChanged / WindowsChanged snapshot on
// connect, so there's no need to prime state with a separate query.
Singleton {
    id: root

    property var workspaces: []
    property var windows: ({})       // id -> window object
    property int focusedWindowId: -1

    readonly property var focusedWindow: {
        const w = root.windows[root.focusedWindowId];
        return w ? w : null;
    }
    readonly property string focusedTitle: root.focusedWindow ? (root.focusedWindow.title || "") : ""
    readonly property string focusedAppId: root.focusedWindow ? (root.focusedWindow.app_id || "") : ""

    // Workspaces belonging to one output, in index order. The bar is
    // per-monitor, so each instance filters to its own screen.
    function workspacesFor(output) {
        return root.workspaces.filter(function (w) {
            return w.output === output;
        }).sort(function (a, b) {
            return a.idx - b.idx;
        });
    }

    function handle(line) {
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }

        const key = Object.keys(ev)[0];
        const d = ev[key];
        if (!key || !d)
            return;

        if (key === "WorkspacesChanged") {
            root.workspaces = d.workspaces.slice();
        } else if (key === "WorkspaceActivated") {
            const target = root.workspaces.find(function (w) {
                return w.id === d.id;
            });
            if (!target)
                return;
            // Activation is per-output; focus is global.
            root.workspaces = root.workspaces.map(function (w) {
                const c = Object.assign({}, w);
                if (c.output === target.output)
                    c.is_active = (c.id === d.id);
                if (d.focused)
                    c.is_focused = (c.id === d.id);
                return c;
            });
        } else if (key === "WorkspaceUrgencyChanged") {
            root.workspaces = root.workspaces.map(function (w) {
                if (w.id !== d.id)
                    return w;
                const c = Object.assign({}, w);
                c.is_urgent = d.urgent;
                return c;
            });
        } else if (key === "WindowsChanged") {
            const m = {};
            let focused = -1;
            for (let i = 0; i < d.windows.length; i++) {
                const w = d.windows[i];
                m[w.id] = w;
                if (w.is_focused)
                    focused = w.id;
            }
            root.windows = m;
            root.focusedWindowId = focused;
        } else if (key === "WindowOpenedOrChanged") {
            const m = Object.assign({}, root.windows);
            m[d.window.id] = d.window;
            root.windows = m;
            if (d.window.is_focused)
                root.focusedWindowId = d.window.id;
        } else if (key === "WindowClosed") {
            const m = Object.assign({}, root.windows);
            delete m[d.id];
            root.windows = m;
            if (root.focusedWindowId === d.id)
                root.focusedWindowId = -1;
        } else if (key === "WindowFocusChanged") {
            root.focusedWindowId = (d.id === null || d.id === undefined) ? -1 : d.id;
        }
    }

    Process {
        id: proc

        running: true
        command: ["niri", "msg", "--json", "event-stream"]

        // Reconnect via a timer rather than re-setting `running` inline, so a
        // niri that isn't up yet doesn't spin us in a hot restart loop.
        onRunningChanged: if (!running)
            retry.start()

        stdout: SplitParser {
            onRead: function (line) {
                root.handle(line);
            }
        }
    }

    Timer {
        id: retry

        interval: 1000
        onTriggered: proc.running = true
    }
}
