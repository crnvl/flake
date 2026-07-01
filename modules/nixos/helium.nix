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

      ExtensionInstallForcelist = [
        "nngceckbapebfimnlniiiahkandclblb;https://clients2.google.com/service/update2/crx" # Bitwarden
        "cdglnehniifkbagbbombnjghhcihifij;https://clients2.google.com/service/update2/crx" # Kagi Search
        "mendokngpagmkejfpmeellpppjgbpdaj;https://clients2.google.com/service/update2/crx" # Kagi Privacy Pass
      ];

      DefaultSearchProviderEnabled = true;
      DefaultSearchProviderName = "Kagi";
      DefaultSearchProviderKeyword = "kagi";
      DefaultSearchProviderSearchURL = "https://kagi.com/search?q={searchTerms}";
      DefaultSearchProviderSuggestURL = "https://kagisuggest.com/api/autosuggest?q={searchTerms}";
    };
  };
}
