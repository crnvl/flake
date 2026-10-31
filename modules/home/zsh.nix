{ config, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = false;
    dotDir = config.home.homeDirectory;

    shellAliases = {
      xm5 = "bluetoothctl power on && bluetoothctl connect AC:80:0A:5A:98:0D";
      xm5off = "bluetoothctl disconnect AC:80:0A:5A:98:0D";
    };

    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 50000;
      save = 50000;
      ignoreDups = true;
      share = true;
    };
  };
}
