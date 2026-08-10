{ lib }:

# Single source of truth for the monochrome palette.
#
# The four base greys are parsed straight out of the Quickshell theme rather
# than duplicated here, so there is exactly one place to change them. Edit
# Theme.qml and the shell live-reloads immediately; the terminal and launcher
# follow on the next rebuild.
#
# Matching is done line by line to avoid relying on how Nix's regex engine
# treats newlines, and throws loudly if the shape of Theme.qml changes.
let
  themeQml = builtins.readFile ./quickshell/Theme.qml;
  lines = lib.splitString "\n" themeQml;

  grab =
    name:
    let
      hits = lib.filter (m: m != null) (
        map (l: builtins.match ".*property color ${name}: \"(#[0-9a-fA-F]{6})\".*" l) lines
      );
    in
    if hits == [ ] then
      throw "palette.nix: could not find `${name}` in modules/home/quickshell/Theme.qml"
    else
      builtins.head (builtins.head hits);

  bg = grab "bg";
  fg = grab "fg";
  dim = grab "dim";
  bright = grab "bright";
in
{
  inherit bg fg dim bright;

  # ── ANSI 16 ────────────────────────────────────────────────────────────────
  # A monochrome terminal has no hue to spend, so this palette encodes
  # *loudness* instead. Colours that conventionally mean "pay attention"
  # (red = errors, yellow = warnings) sit high on the ramp; colours that mean
  # "context" (blue = paths and comments) sit low. Steps are ~0x12 apart so
  # adjacent entries stay distinguishable as greys.
  #
  # The tradeoff is real and worth stating: you lose the ability to tell red
  # from green at a glance. Diffs and test output read by brightness now, not
  # by colour.
  ansi = {
    black = bg;
    blue = "#606060";
    magenta = "#727272";
    green = "#848484";
    cyan = "#969696";
    yellow = "#a8a8a8";
    red = "#bababa";
    white = fg;
  };

  ansiBright = {
    black = dim;
    blue = "#828282";
    magenta = "#949494";
    green = "#a6a6a6";
    cyan = "#b8b8b8";
    yellow = "#cacaca";
    red = "#dcdcdc";
    white = bright;
  };
}
