{ config, pkgs, ... }:

{
  programs.firefox = {
    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DontCheckDefaultBrowser = true;
      DisablePocket = true;
      SearchBar = "unified";
    };

    profiles = {
      default = {
        id = 0;
        name = "default";
        isDefault = true;
      };
    };
  };
}
