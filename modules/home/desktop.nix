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
      settings.AddKeysToAgent = "yes";
    };
  };

  home = {
    file.".config/wallpaper".source = ../../assets/wallpaper.jpg;

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

    sessionVariables = {
      CARGO_HOME = "$HOME/.local/share/cargo";
      HISTFILE = "$HOME/.local/state/zsh/history";
    };

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
}
