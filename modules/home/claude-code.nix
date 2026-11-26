{ ... }:

{
  # Sign in once per machine: run `claude` and follow the login prompt
  # (Claude Pro/Max account or an Anthropic Console API key).
  # The nixpkgs wrapper already sets DISABLE_AUTOUPDATER, since nix manages the package.
  programs.claude-code = {
    enable = true;

    # Merged into a writable ~/.claude/settings.json on activation, so /model,
    # /config and "always allow" answers still save between sessions. The
    # values below are reapplied on every switch.
    mutableSettings = true;

    settings = {
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";

      model = "opus";

      # Background work (titles, summaries) on Sonnet, like OpenCode's small_model.
      env.ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-sonnet-5-5";
    };
  };
}
