{ pkgs, ... }:

{
  programs.opencode = {
    enable = true;

    # nixpkgs' node_modules hash for opencode 2.2.5 doesn't match what bun
    # actually fetches. Drop this once nixpkgs ships a corrected hash.
    package = pkgs.opencode.overrideAttrs (old: {
      node_modules = old.node_modules.overrideAttrs {
        outputHash = "sha256-prx9dX7kUvs/E3zopkaPk5LXh3xJAy5sZeum/W8L7cA=";
      };
    });

    # written to ~/.config/opencode/opencode.json
    settings = {
      "$schema" = "https://opencode.ai/config.json";

      # default model served through the Copilot provider
      model = "github-copilot/claude-fable-5";
      small_model = "github-copilot/claude-sonnet-5";

      autoupdate = false; # nix manages the package
    };
  };
}
