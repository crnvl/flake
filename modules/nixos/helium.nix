{ inputs, ... }:

let
  # Helium strips prodversion from update checks, so Google's own endpoint
  # answers "noupdate"; its Web Store proxy (Helium services) fills it in.
  webStore = "https://services.helium.imput.net/ext/";

  forceInstall = extra: {
    installation_mode = "force_installed";
    update_url = webStore;
  } // extra;

  bitwarden = "nngceckbapebfimnlniiiahkandclblb";
in
{
  imports = [ inputs.helium.nixosModules.default ];

  programs.helium = {
    enable = true;

    flags = [ "--force-dark-mode" ];

    policies = {
      PasswordManagerEnabled = false;
      BrowserSignin = 0;

      ShowHomeButton = true;
      BookmarkBarEnabled = true;

      NewTabPageLocation = "https://kagi.com?year=1996";
      HomepageIsNewTabPage = true;

      DefaultSearchProviderEnabled = true;
      DefaultSearchProviderName = "Kagi";
      DefaultSearchProviderKeyword = "kagi";
      DefaultSearchProviderSearchURL = "https://kagi.com/search?q={searchTerms}";
      DefaultSearchProviderSuggestURL = "https://kagisuggest.com/api/autosuggest?q={searchTerms}";

      ExtensionSettings = {
        ${bitwarden} = forceInstall { toolbar_pin = "force_pinned"; };
        "cdglnehniifkbagbbombnjghhcihifij" = forceInstall { }; # Kagi Search
        "mendokngpagmkejfpmeellpppjgbpdaj" = forceInstall { }; # Kagi Privacy Pass
      };

      # Bitwarden reads this from chrome.storage.managed (its managed_schema.json).
      "3rdparty".extensions.${bitwarden}.environment.base = "https://vault.shimme.rs";
    };
  };
}
