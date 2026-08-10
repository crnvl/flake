pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// The notification daemon.
//
// This single object replaced the entire dbus-monitor -> awk -> statefile ->
// python-scroller pipeline in the old waybar.nix, plus the notification-feed
// systemd unit, plus swaync itself -- all of which are now deleted.
// Notifications arrive as structured objects with summary, body, urgency and
// actions already parsed.
//
// IMPORTANT: only one process can own org.freedesktop.Notifications. Nothing
// else on the system claims it now, but running a second Quickshell instance
// against the source tree while the niri-spawned one is alive will make the
// second fail to bind -- and notifications silently vanish, since the loser
// just doesn't get them. Kill the first one when iterating.
Singleton {
    id: root

    // Newest first, capped so a notification storm can't fill the screen.
    readonly property int maxVisible: 5

    readonly property var list: {
        const all = server.trackedNotifications.values.slice();
        all.reverse();
        return all.slice(0, root.maxVisible);
    }

    readonly property int count: server.trackedNotifications.values.length

    function dismissAll() {
        const all = server.trackedNotifications.values.slice();
        for (let i = 0; i < all.length; i++)
            all[i].dismiss();
    }

    NotificationServer {
        id: server

        bodySupported: true
        // We render on a character grid with PlainText, so advertising markup
        // would be a lie -- clients would send <b> tags we'd draw literally.
        bodyMarkupSupported: false
        actionsSupported: false
        imageSupported: false
        // Don't re-emit across hot reloads; keeps the screen clean while
        // iterating on the design.
        keepOnReload: false

        onNotification: function (n) {
            n.tracked = true;
        }
    }
}
