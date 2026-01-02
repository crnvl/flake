{ config, pkgs, ... }:

{
  home.username = "aleph";
  home.homeDirectory = "/home/aleph";
  home.stateVersion = "25.11";

  home.sessionVariables = {
    EDITOR = "code";
    LANG = "en_US.UTF-8";
  };

  programs.zsh.enable = true;

  programs.git = {
    enable = true;
    userName = "67";
    userEmail = "support@linux.com";
  };

  programs.firefox = import ./../../../home/firefox.nix;
}
