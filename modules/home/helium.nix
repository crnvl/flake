{ inputs, ... }:

{
  imports = [ inputs.helium-nix.homeManagerModules.helium ];

  programs.helium = {
    enable = true;
    defaultBrowser = true;

    extensions = [
      {
        id = "nngceckbapebfimnlniiiahkandclblb";
        hash = "sha256-isQi2O13OUV39zR7Z1KkpKL7QJxPWbQw2lMLE7AO1E0=";
      } # Bitwarden
      {
        id = "cdglnehniifkbagbbombnjghhcihifij";
        hash = "sha256-weiUUUiZeeIlz/k/d9VDSKNwcQtmAahwSIHt7Frwh7E=";
      } # Kagi Search
      {
        id = "mendokngpagmkejfpmeellpppjgbpdaj";
        hash = "sha256-GIiQvDDiQyktDyFUMpmRfgskks88QysxbaaFVzfVTsI=";
      } # Kagi Privacy Pass
    ];

    extraFlags = [ "--force-dark-mode" ];

    extraPolicies = {
      PasswordManagerEnabled = false;
      BrowserSignin = 0;

      DefaultSearchProviderEnabled = true;
      DefaultSearchProviderName = "Kagi";
      DefaultSearchProviderKeyword = "kagi";
      DefaultSearchProviderSearchURL = "https://kagi.com/search?q={searchTerms}";
      DefaultSearchProviderSuggestURL = "https://kagisuggest.com/api/autosuggest?q={searchTerms}";
    };

    preferences = {
      browser.show_home_button = true;
      bookmark_bar.show_on_all_tabs = true;
    };
  };
}
