{ pkgs, ... }:

{
  programs = {
    alacritty.enable = true;
    fuzzel.enable = true;

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks."*" = {
        addKeysToAgent = "yes";
      };
    };
  };

  home.packages = with pkgs; [
    zed-editor
  ];
}
