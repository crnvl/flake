{ pkgs, ... }:

{
  programs = {
    alacritty.enable = true;
    fuzzel.enable = true;

    ssh = {
      enable = true;
      matchBlocks."*" = {
        addKeysToAgent = "yes";
      };
    };
  };

  home.packages = with pkgs; [
    zed-editor
  ];
}
