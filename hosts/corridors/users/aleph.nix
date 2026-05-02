{ ... }:

{
  imports = [
    ./../../../modules/home/desktop.nix
    ./../../../modules/home/firefox.nix
    ./../../../modules/home/git.nix
    ./../../../modules/home/niri.nix
    ./../../../modules/home/waybar.nix
  ];

  home = {
    username = "aleph";
    homeDirectory = "/home/aleph";
    stateVersion = "25.11";
  };

  programs = {
    niri.settings = {
      input = {
        keyboard = {
          xkb.layout = "us";
          numlock = true;
        };
      };
    };

    git = {
      settings = {
        user = {
          name = "67";
          email = "support@linux.com";
        };

        gpg.format = "ssh";
      };

      signing = {
        key = "/home/aleph/.ssh/id_ed25519.pub";
        signByDefault = true;
      };
    };
  };
}
