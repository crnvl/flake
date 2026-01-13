{ pkgs, config, ... }:

{
  imports = [
    ./../../../home/firefox.nix
    ./../../../home/git.nix
    ./../../../home/alacritty.nix
    ./../../../home/fuzzel.nix
    ./../../../home/vscode.nix
    ./../../../home/yazi.nix
    ./../../../home/niri.nix
    ./../../../home/waybar.nix
  ];

  home.username = "aleph";
  home.homeDirectory = "/home/aleph";
  home.stateVersion = "25.11";
  home.file.".config/waybar/style.css".source = ./waybar/style.css;

  home.pointerCursor = {
    size = 24;
    name = "Vimix-cursors";
    package = pkgs.vimix-cursors;
  };

  home.packages = with pkgs; [
    signal-desktop
    pokemmo-installer
    httptoolkit
    mitmproxy
    frida-tools
  ];

  programs = {
    git = {
      signing = {
        key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH++Jm6a+gQf5yEdTzT5ozuIQdkYb2w98UxsX2I1YJlg aleph@cats";
        signByDefault = true;
      };

      settings = {
        gpg = {
          format = "ssh";
        };
      };
    };
  };

  home.sessionVariables = {
    EDITOR = "code";
    LANG = "en_US.UTF-8";
  };
}
