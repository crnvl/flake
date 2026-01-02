{ config, pkgs, ... }:

{
    home = {
        username = "aleph";
        homeDirectory = "/home/aleph";

        sessionVariables = {
            EDITOR = "code";
            LANG = "en_US.UTF-8";
        };
    };

    imports = [
        ./home/firefox.nix
    ];
}