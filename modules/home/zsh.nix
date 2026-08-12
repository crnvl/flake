{ config, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = false;
    dotDir = config.home.homeDirectory;

    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      ignoreDups = true;
      share = true;
    };
  };
}
