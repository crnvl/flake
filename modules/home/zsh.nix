{ config, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = false;
    dotDir = config.home.homeDirectory;

    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 50000;
      save = 50000;
      ignoreDups = true;
      share = true;
    };
  };
}
