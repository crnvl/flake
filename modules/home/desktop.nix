{ lib, pkgs, ... }:

{
  imports = [
    ./firefox.nix
    ./niri.nix
    ./waybar.nix
  ];

  xdg.enable = true;

  programs = {
    alacritty.enable = true;
    fuzzel.enable = true;

    git = {
      enable = true;
      settings = {
        user = {
          name = "67";
          email = "support@linux.com";
        };
        gpg.format = "ssh";
      };

      signing = {
        key = "~/.ssh/id_ed25519.pub";
        signByDefault = true;
      };
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "Host *" = {
          AddKeysToAgent = "yes";
        };
      };
    };
  };

  services.swaync = {
    enable = true;
    settings = {
      positionX = "right";
      positionY = "top";
      control-center-width = 400;
      control-center-height = 600;
      fit-to-screen = false;
      # No popup toasts: notifications still land in the control center.
      notification-visibility = {
        all = {
          state = "muted";
          "app-name" = ".*";
        };
      };
    };
    style = ''
      * {
        font-family: "MS Sans Serif";
        font-size: 14px;
      }

      .control-center {
        background-color: #c4c0c1;
        border-top: 1px solid #ffffff;
        border-left: 1px solid #ffffff;
        box-shadow: 2px 2px 0px 2px rgba(0, 0, 0, 0.75);
        color: #1d2021;
        padding: 8px;
      }

      .control-center .widget-title > label {
        color: #1d2021;
        font-weight: bold;
      }

      .control-center .widget-title button {
        background-color: #c4c0c1;
        color: #1d2021;
        border-top: 1px solid #ffffff;
        border-left: 1px solid #ffffff;
        box-shadow: 2px 2px 0px 0px rgba(0, 0, 0, 0.75);
        padding: 2px 8px;
      }

      .notification-row .notification-background,
      .notification {
        background-color: #c4c0c1;
        border-top: 1px solid #ffffff;
        border-left: 1px solid #ffffff;
        box-shadow: 2px 2px 0px 0px rgba(0, 0, 0, 0.75);
        margin: 6px 4px;
        padding: 0;
      }

      .notification-content {
        color: #1d2021;
        padding: 6px 8px;
      }

      .notification-content .summary { color: #1d2021; font-weight: bold; }
      .notification-content .body    { color: #1d2021; }
      .notification-content .time    { color: #504945; }

      .close-button {
        background-color: #cc241d;
        color: #ffffff;
        border-top: 1px solid #ffffff;
        border-left: 1px solid #ffffff;
        box-shadow: 1px 1px 0px 0px rgba(0, 0, 0, 0.75);
        margin: 4px;
        padding: 0 6px;
      }
    '';
  };

  home = {
    file.".config/wallpaper".source = ../../assets/wallpaper.jpg;

    username = "aleph";
    homeDirectory = "/home/aleph";
    stateVersion = "25.11";

    pointerCursor = {
      enable = true;
      size = 24;
      name = "Vimix-cursors";
      package = pkgs.vimix-cursors;
    };

    sessionVariables = {
      EDITOR = "zeditor";
      LANG = "en_US.UTF-8";
      CARGO_HOME = "$HOME/.local/share/cargo";
      HISTFILE = "$HOME/.local/state/zsh/history";
    };

    packages = with pkgs; [
      awww
      zed-editor
      kdePackages.dolphin
      feather
      fluffychat
      signal-desktop
      spotify
      qbittorrent
      vesktop
      ncdu
      xdg-ninja
      google-chrome

      (tor-browser.override {
        extraPrefs = ''
          lockPref("javascript.enabled", false);

          lockPref("javascript.options.ion", false);
          lockPref("javascript.options.baselinejit", false);
          lockPref("javascript.options.native_regexp", false);
          lockPref("javascript.options.wasm", false);
          lockPref("mathml.disabled", true);
          lockPref("svg.disabled", true);
          lockPref("gfx.font_rendering.opentype_svg.enabled", false);
        '';
      })
    ];

    activation = {
      zshStateDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.local/state/zsh"
        if [ -f "$HOME/.zsh_history" ] && [ ! -f "$HOME/.local/state/zsh/history" ]; then
          mv "$HOME/.zsh_history" "$HOME/.local/state/zsh/history"
        fi
      '';
      setWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if ${pkgs.procps}/bin/pgrep -x awww-daemon > /dev/null 2>&1; then
          ${pkgs.awww}/bin/awww img "$HOME/.config/wallpaper" \
            --transition-type grow --transition-fps 60 --transition-duration 1 || true
        fi
      '';
    };
  };

  gtk = {
    enable = true;
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig."gtk-application-prefer-dark-theme" = true;
  };

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk3";
  };
}
