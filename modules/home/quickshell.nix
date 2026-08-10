{ pkgs, ... }:

# Monochrome TUI shell built on Quickshell.
#
# This is the whole desktop shell: top bar, fullscreen background dashboard
# (in place of a wallpaper), volume/brightness OSD, and the notification
# daemon. It replaced waybar and swaync outright -- neither is installed.
#
# niri launches it from spawn-at-startup in modules/home/niri.nix:
#
#   { argv = [ "quickshell" "-c" "tui" ]; }
#
# `-c tui` resolves to ~/.config/quickshell/tui, which is the symlink created
# below. Quickshell is in nixpkgs (0.3.0), so no new flake input is required.
#
# ── Working on the QML ───────────────────────────────────────────────────────
# Quickshell hot-reloads on file save, but the symlink points at the *store*
# copy, so editing the checkout doesn't reach the running shell. To iterate
# without rebuilding, run a second instance straight off the source tree:
#
#   quickshell -p ~/flake/modules/home/quickshell
#
# Kill the niri-spawned one first, or the two will fight over the
# org.freedesktop.Notifications DBus name (only one process may own it).
#
# ── Layout ───────────────────────────────────────────────────────────────────
# All QML lives in a single flat directory on purpose. Quickshell resolves
# implicit component imports per-directory, so splitting into subdirs means
# every file needs explicit import paths for very little gain.
{
  home.packages = [ pkgs.quickshell ];

  xdg.configFile."quickshell/tui".source = ./quickshell;
}
