{ pkgs, ... }:

{
  imports = [
    ./../../../modules/home/desktop.nix
  ];

  home = {
    username = "aleph";
    homeDirectory = "/home/aleph";
    stateVersion = "25.11";
    pointerCursor = {
      size = 24;
      name = "Vimix-cursors";
      package = pkgs.vimix-cursors;
    };

    sessionVariables = {
      EDITOR = "zeditor";
      LANG = "en_US.UTF-8";
    };

    packages = with pkgs; [
      httptoolkit
      mitmproxy
      jadx
      apktool
      apksigner
      android-studio
      python315
      python314Packages.pip
      httpx
      ghidra-bin
      spotify
      vlc
      kdePackages.dolphin
      inetutils
      vesktop
    ];
  };

  programs = {
    niri.settings = {
      input = {
        keyboard = {
          xkb.layout = "de";
          numlock = true;
        };

        touchpad = {
          tap = true;
          natural-scroll = true;
        };
      };
    };
  };
}
