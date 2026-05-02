{ pkgs, ... }:

{
  programs = {
    alacritty.enable = true;
    fuzzel.enable = true;
  };

  home.packages = with pkgs; [
    zed-editor
  ];
}
