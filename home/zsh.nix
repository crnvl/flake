{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;

    enableCompletion = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      theme = "agnoster";
      plugins = [
        "git"
        "sudo"
        "docker"
        "kubectl"
        "history"
      ];
    };

    shellAliases = {
      rebuild = "sudo nixos-rebuild switch --flake .#";
    };
  };
}
