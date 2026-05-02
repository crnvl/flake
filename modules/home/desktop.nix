{ pkgs, ... }:

{
  programs = {
    alacritty.enable = true;
    fuzzel.enable = true;

    ssh = {
      enable = true;
      addKeysToAgent = "yes";
    };
  };

  home.packages = with pkgs; [
    zed-editor
  ];
}
