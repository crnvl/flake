{ config, pkgs, ... }:

{
  programs.firefox.enable = true;

  programs.firefox.extensions = [
    pkgs.mozilla.bitwarden
  ];

  xdg.defaultApplications.webBrowser = "firefox";
}
