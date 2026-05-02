{ pkgs, ... }:

{
  programs = {
    alacritty.enable = true;
    fuzzel.enable = true;
  };

  home.packages = with pkgs; [
    zed-editor
  ];

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
  };
}
