{ inputs, ... }:

{
  imports = [ inputs.helium-nix.nixosModules.default ];

  programs.helium = {
    enable = true;

    flags = [ "--force-dark-mode" ];

    policies = {
      PasswordManagerEnabled = false;
      BrowserSignin = 0;

      ShowHomeButton = true;
      BookmarkBarEnabled = true;
    };
  };
}
