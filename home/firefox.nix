{ config, pkgs, inputs, ... }:

let
  lock-false = {
    Value = false;
    Status = "locked";
  };
  lock-empty-string = {
    Value = "";
    Status = "locked";
  };
in
{
  programs.firefox = {
    enable = true;

    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DontCheckDefaultBrowser = true;
      DisablePocket = true;
      SearchBar = "unified";

      Preferences = {
        "extensions.pocket.enabled" = lock-false;
        "browser.newtabpage.pinned" = lock-empty-string;
        "browser.topsites.contile.enabled" = lock-false;
        "browser.newtabpage.activity-stream.showSponsored" = lock-false;
        "browser.newtabpage.activity-stream.system.showSponsored" = lock-false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = lock-false;
      };
    };

    profiles = {
      default = {
        id = 0;
        name = "default";
        isDefault = true;

        settings = {
          extensions = with inputs.firefox-addons.packages.${pkgs.system}; [
            bitwarden
            ublock-origin
          ];
        };
      };
    };
  };
}
