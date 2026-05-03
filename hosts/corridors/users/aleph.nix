{ pkgs, ... }:

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
    pointerCursor = {
      size = 24;
      name = "Vimix-cursors";
      package = pkgs.vimix-cursors;
    };

    sessionVariables = {
      EDITOR = "zeditor";
      LANG = "en_US.UTF-8";
    };

    packages = with pkgs; [
      signal-desktop
      spotify
      qbittorrent
      vesktop
    ];
  };

  programs = {
    fuzzel.settings = {
      main = {
        font = "monospace:size=14";
      };
    };

    niri.settings = {
      input = {
        keyboard = {
          xkb.layout = "us";
          numlock = true;
        };
      };

      spawn-at-startup = [
        {
          argv = [
            "niri"
            "msg"
            "action"
            "focus-monitor-down"
          ];
        }
      ];

      outputs = {
        "DP-3" = {
          mode = {
            width = 1920;
            height = 1080;
            refresh = 75.002;
          };

          position = {
            x = 0;
            y = 0;
          };
        };

        "HDMI-A-1" = {
          mode = {
            width = 1920;
            height = 1080;
            refresh = 60.0;
          };

          position = {
            x = 0;
            y = -1080;
          };
        };

        "DP-2" = {
          mode = {
            width = 1920;
            height = 1080;
            refresh = 75.002;
          };

          position = {
            x = 1920;
            y = 0;
          };
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
