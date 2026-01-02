{ config, pkgs, ... }:

{
  imports = [
    ./../../../home/firefox.nix
    ./../../../home/git.nix
    ./../../../home/zsh.nix
  ];

  home.username = "aleph";
  home.homeDirectory = "/home/aleph";
  home.stateVersion = "25.11";

  home.sessionVariables = {
    EDITOR = "code";
    LANG = "en_US.UTF-8";
  };
}
