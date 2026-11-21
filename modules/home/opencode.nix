{
  config,
  lib,
  pkgs,
  ...
}:

let
  # llama-swap on shimmers (modules/nixos/services/llm.nix), forwarded to the
  # same port here by the tunnel below.
  llmPort = 8090;
  llmModel = "shimmers/qwen3.6-35b-a3b-uncensored";
  docsPython = pkgs.python3.withPackages (p: [
    p.mcp
    p.httpx
    p.anyio
  ]);

  # The session and its housekeeping always use shimmers. The MCP worker makes
  # separate, tool-less cloud requests for public documentation or a public brief.
  docsWorkspace = {
    "$schema" = "https://opencode.ai/config.json";
    model = llmModel;
    mcp.servers.publicdocs = {
      type = "local";
      cwd = "/";
      codemode = false;
      command = [
        "${docsPython}/bin/python3"
        "${./opencode-public-docs.py}"
        "${config.programs.opencode.package}/bin/opencode"
      ];
      timeout.execution = 60000;
    };
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

  home.file."redteam/opencode.json".text = builtins.toJSON (
    docsWorkspace // { default_agent = "redteam"; }
  );

  # Opt-in space for public questions: the local advisor picks when to consult
  # the reviewer. No need to mark each question as a shareable brief here.
  home.file."public-docs/opencode.json".text = builtins.toJSON (
    lib.recursiveUpdate docsWorkspace {
      default_agent = "public-advisor";
      # Use Qwen's fast path for dispatch and synthesis in this workspace.
      providers.shimmers.models."qwen3.6-35b-a3b-uncensored".body.chat_template_kwargs.enable_thinking =
        false;
      mcp.servers.publicdocs.command = docsWorkspace.mcp.servers.publicdocs.command ++ [
        "${config.home.homeDirectory}/public-docs"
      ];
      agents.public-advisor = {
        description = "Public technical Q&A with optional cloud review";
        mode = "primary";
        steps = 3;
        system = ''
          Answer technical and defensive engineering questions. Use publicdocs_research for vendor
          references, and publicdocs_reason for complex comparisons, design reviews or diagnoses.
          A fresh question in this workspace is public; the reviewer sees only the user's latest
          question and cannot inspect files. Use its evidence to answer; report missing information.
        '';
        permissions = [
          {
            action = "*";
            resource = "*";
            effect = "deny";
          }
          {
            action = "publicdocs_*";
            resource = "*";
            effect = "allow";
          }
        ];
      };
    }
  );

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
