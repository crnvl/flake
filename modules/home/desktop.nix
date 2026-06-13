{ pkgs, ... }:

{
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
      matchBlocks."*" = {
        addKeysToAgent = "yes";
      };
    };
  };

  home.packages = with pkgs; [
    zed-editor
    kdePackages.dolphin
    feather
    fluffychat

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
}
