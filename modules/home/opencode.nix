{ ... }:

{
  programs.opencode = {
    enable = true;

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
