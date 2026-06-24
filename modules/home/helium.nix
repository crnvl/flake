{ inputs, ... }:

{
  imports = [ inputs.helium-nix.homeManagerModules.helium ];

  programs.helium = {
    enable = true;
    defaultBrowser = true;

    extensions = [ ];

    extraFlags = [ "--force-dark-mode" ];

    extraPolicies = {
      PasswordManagerEnabled = false;
      BrowserSignin = 0;
    };

    preferences = {
      browser.show_home_button = true;
      bookmark_bar.show_on_all_tabs = true;
    };
  };

}
