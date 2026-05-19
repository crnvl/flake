{ ... }:

{
  programs.zsh = {
    enable = true;

    enableCompletion = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      vr-audio = ''wpctl set-default $(pw-cli list-objects Node | grep -B5 'node.name = "wivrn.sink"' | grep "id " | head -1 | grep -oE "id [0-9]+" | grep -oE "[0-9]+")'';
    };

    ohMyZsh = {
      enable = true;
      theme = "gentoo";
      plugins = [
        "git"
        "sudo"
        "history"
      ];
    };
  };
}
