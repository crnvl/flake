{ config, pkgs, ... }:

{
  imports = [
    ./../../../home/firefox.nix
    ./../../../home/git.nix
    ./../../../home/zsh.nix
    ./../../../home/alacritty.nix
    ./../../../home/fuzzel.nix
    ./../../../home/vscode.nix
    ./../../../home/yazi.nix
  ];

  home.username = "aleph";
  home.homeDirectory = "/home/aleph";
  home.stateVersion = "25.11";

  home.file.".ssh/id_rsa" = {
    source = /etc/nixos/secrets/id_rsa_git;
    mode = "0600";
  };
  home.file.".ssh/id_rsa.pub".source = /etc/nixos/secrets/id_rsa_git.pub;

  home.sessionVariables.GIT_SSH_COMMAND = "ssh -i ~/.ssh/id_rsa_git -o IdentitiesOnly=yes";

  home.sessionVariables = {
    EDITOR = "code";
    LANG = "en_US.UTF-8";
  };
}
