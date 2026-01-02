{ config, pkgs, ... }:

{
    home = {
        username = "aleph";
        homeDirectory = "/home/aleph";
        stateVersion = "25.11";

        sessionVariables = {
            EDITOR = "code";
            LANG = "en_US.UTF-8";
        };
    };

    programs.firefox = import ./home/firefox.nix;
}