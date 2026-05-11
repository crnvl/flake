{ pkgs, ... }:

{
  imports = [
    ./../../../modules/home/desktop.nix
    ./../../../modules/home/firefox.nix
    ./../../../modules/home/niri.nix
    ./../../../modules/home/waybar.nix
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
      signal-desktop
      pokemmo-installer
      httptoolkit
      mitmproxy
      frida-tools
      jadx
      apktool
      apksigner
      zulu8
      android-studio
      vagrant
      python315
      python314Packages.pip
      httpx
      ghidra-bin
      spotify
      vlc
      qbittorrent
      kdePackages.dolphin
      inetutils
      bitwig-studio
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

    git = {
      settings = {
        user = {
          name = "67";
          email = "support@linux.com";
        };
        gpg = {
          format = "ssh";
        };
      };

      signing = {
        key = "/home/aleph/.ssh/id_ed25519.pub";
        signByDefault = true;
      };
    };
  };
}
