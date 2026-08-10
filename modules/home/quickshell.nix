{ pkgs, ... }:

# Monochrome TUI shell built on Quickshell.
#
# NOTE: this module is intentionally NOT imported by desktop.nix yet, so it has
# zero effect on your system until you opt in. To try it:
#
#   1. Add `./quickshell.nix` to the imports list in modules/home/desktop.nix
#   2. Rebuild, then run:  quickshell -p ~/.config/quickshell/tui
#
# The bar anchors to the TOP of the screen, so it can run alongside the
# existing waybar (which sits at the bottom) while you compare them.
#
# Quickshell is in nixpkgs (0.3.0), so no new flake input is required.
#
# ── Notifications ────────────────────────────────────────────────────────────
# The config includes a notification daemon (Notifications.qml). Only one
# process may own the org.freedesktop.Notifications DBus name, so swaync MUST
# be stopped before it will bind:
#
#   systemctl --user stop swaync     # ephemeral; returns on next login
#
# To adopt it permanently, delete the `services.swaync` block from
# modules/home/desktop.nix. At that point the following also become dead code
# and can be removed from modules/home/waybar.nix:
#
#   - notificationWriter        (dbus-monitor | awk pipeline)
#   - notificationTicker        (the python scroller)
#   - systemd.user.services.notification-feed
#
# volume-notify / brightness-notify keep working unchanged -- they just
# notify into this daemon instead of swaync.
{
  home.packages = [ pkgs.quickshell ];

  xdg.configFile."quickshell/tui".source = ./quickshell;

  # When you're ready to make it permanent, drop this into the
  # spawn-at-startup list in modules/home/niri.nix instead of waybar:
  #
  #   { argv = [ "quickshell" "-p" "/home/aleph/.config/quickshell/tui" ]; }
}
