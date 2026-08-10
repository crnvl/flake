{ lib, ... }:

let
  palette = import ./palette.nix { inherit lib; };

  # fuzzel wants RRGGBBAA with no leading '#'.
  fz = c: (lib.removePrefix "#" c) + "ff";
in
{
  # Terminal and launcher themed to match the Quickshell palette.
  #
  # Emphasis follows the same rule as the shell: reverse video rather than
  # colour. Selection in both apps swaps foreground and background instead of
  # tinting, which is what a monochrome terminal actually did.
  programs.alacritty.settings = {
    font = {
      normal = {
        family = "JetBrainsMono Nerd Font";
        style = "Regular";
      };
      size = lib.mkDefault 11;
    };

    window = {
      padding = {
        x = 10;
        y = 10;
      };
      dynamic_padding = true;
      decorations = "none";
      opacity = 1.0;
    };

    cursor = {
      style = {
        shape = "Block";
        # A blinking cursor is a modern affectation; block-and-steady is the
        # older look and sits better next to the rest of this.
        blinking = "Off";
      };
    };

    colors = {
      primary = {
        background = palette.bg;
        foreground = palette.fg;
      };

      cursor = {
        text = palette.bg;
        cursor = palette.fg;
      };

      selection = {
        text = palette.bg;
        background = palette.fg;
      };

      normal = palette.ansi;
      bright = palette.ansiBright;
    };
  };

  programs.fuzzel.settings = {
    main = {
      # mkDefault so corridors can keep overriding this per-host.
      font = lib.mkDefault "JetBrainsMono Nerd Font:size=13";
      lines = 12;
      width = 48;
      horizontal-pad = 16;
      vertical-pad = 12;
      inner-pad = 4;
    };

    border = {
      width = 1;
      # Square corners. This is the single most important line in the file.
      radius = 0;
    };

    colors = {
      background = fz palette.bg;
      text = fz palette.fg;
      match = fz palette.bright;
      selection = fz palette.fg;
      selection-text = fz palette.bg;
      selection-match = fz palette.bg;
      border = fz palette.dim;
    };
  };
}
