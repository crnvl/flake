{ pkgs, ... }:

# Monochrome TUI shell built on Quickshell.
#
# Config is installed to ~/.config/quickshell/tui, so it runs as:
#
#   quickshell -c tui
#
# which is what niri's spawn-at-startup uses (see niri.nix). Quickshell hot-
# reloads on save, so you can edit the QML in this repo's checkout and see
# changes live -- though the running instance reads the ~/.config copy, so
# use `quickshell -p ./modules/home/quickshell` when iterating.
#
# Quickshell is in nixpkgs (0.3.0), so no flake input is required.
{
  home.packages = [ pkgs.quickshell ];

  xdg.configFile."quickshell/tui".source = ./quickshell;
}
