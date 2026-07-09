{ pkgs, ... }:

{
  imports = [
    ./../../../modules/home/desktop.nix
  ];

  home = {
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
