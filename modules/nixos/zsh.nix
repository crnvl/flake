{ ... }:

{
  programs.zsh = {
    enable = true;

    enableCompletion = true;
    syntaxHighlighting.enable = true;

    ohMyZsh = {
      enable = true;
      theme = "gentoo";
      plugins = [
        "git"
        "sudo"
        "docker"
        "kubectl"
        "history"
      ];
    };
  };
}
