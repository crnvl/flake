pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// The notification daemon.
//
// This single object replaces the entire dbus-monitor -> awk -> statefile ->
// python-scroller pipeline in modules/home/waybar.nix, plus the
// notification-feed systemd unit, plus swaync itself. Notifications arrive as
// structured objects with summary, body, urgency, and actions already parsed.
//
// IMPORTANT: only one process can own org.freedesktop.Notifications. swaync
// must be disabled before this will bind (see modules/home/quickshell.nix).
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
