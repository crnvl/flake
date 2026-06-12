{ pkgs, ... }:

{
  programs = {
    alacritty.enable = true;
    fuzzel.enable = true;

    git = {
      enable = true;
      settings = {
        user = {
          name = "67";
          email = "support@linux.com";
        };
        gpg.format = "ssh";
      };

      signing = {
        key = "~/.ssh/id_ed25519.pub";
        signByDefault = true;
      };
    };

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
    kdePackages.dolphin
    feather
  ];
}
