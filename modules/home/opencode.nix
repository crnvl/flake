{ pkgs, ... }:

let
  # llama-swap on shimmers (modules/nixos/services/llm.nix), forwarded to the
  # same port here by the tunnel below.
  llmPort = 8090;
  llmModel = "shimmers/qwen3.6-35b-a3b-uncensored";
in
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

      providers.shimmers = {
        name = "shimmers";
        package = "@opencode/ai/providers/openai-compatible";
        settings = {
          baseURL = "http://127.0.0.1:${toString llmPort}/v1";
          # CPU inference: the first token can take minutes on a long prompt,
          # longer still when the model has to be loaded first.
          headerTimeout = 900000;
        };
        models."qwen3.6-35b-a3b-uncensored" = {
          name = "Qwen3.6 35B-A3B Uncensored (shimmers)";
          capabilities = {
            tools = true;
            input = [ "text" ];
            output = [ "text" ];
            reasoning.supported = true;
          };
          compatibility.reasoningField = "reasoning_content";
          limit = {
            context = 131072;
            output = 32768;
          };
          variants = [
            {
              id = "instant";
              body.chat_template_kwargs.enable_thinking = false;
            }
          ];
        };
      };

      agents.redteam = {
        description = "Security work on the self-hosted uncensored model on shimmers";
        mode = "primary";
        model = llmModel;
        color = "#d14b4b";
      };
    };
  };

  # Engagement workspace: anything started under ~/redteam can only use the
  # self-hosted model, so prompts and findings never reach a cloud provider.
  # Titles and summaries are redirected too, since they'd otherwise go to
  # small_model on Copilot.
  home.file."redteam/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    model = llmModel;
    default_agent = "redteam";
    policies = [
      {
        action = "provider.use";
        resource = "*";
        effect = "deny";
      }
      {
        action = "provider.use";
        resource = "shimmers";
        effect = "allow";
      }
    ];
    agents = {
      title.model = "${llmModel}#instant";
      summary.model = "${llmModel}#instant";
      compaction.model = llmModel;
    };
  };

  systemd.user.services.shimmers-llm-tunnel = {
    Unit.Description = "SSH tunnel to the self-hosted LLM on shimmers";
    Service = {
      ExecStart = builtins.concatStringsSep " " [
        "${pkgs.openssh}/bin/ssh -N"
        "-o BatchMode=yes"
        "-o ExitOnForwardFailure=yes"
        "-o ServerAliveInterval=30"
        "-o ServerAliveCountMax=3"
        "-o StrictHostKeyChecking=accept-new"
        "-L 127.0.0.1:${toString llmPort}:127.0.0.1:${toString llmPort}"
        "aleph@shimme.rs"
      ];
      Restart = "always";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
