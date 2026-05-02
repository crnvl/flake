{ pkgs, ... }:

{
  imports = [
    ./../../../modules/home/firefox.nix
    ./../../../modules/home/git.nix
    ./../../../modules/home/alacritty.nix
    ./../../../modules/home/fuzzel.nix
    ./../../../modules/home/vscode.nix
    ./../../../modules/home/yazi.nix
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
      EDITOR = "code";
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
        key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH++Jm6a+gQf5yEdTzT5ozuIQdkYb2w98UxsX2I1YJlg aleph@cats";
        signByDefault = true;
      };
    };
  };
}
