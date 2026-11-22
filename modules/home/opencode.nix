{
  config,
  lib,
  pkgs,
  ...
}:

let
  # The same Qwen3.6 model ID, now served by the Rust GPU gateway through SSH.
  llmModel = "shimmers/qwen3.6-35b-a3b-uncensored";
  docsPython = pkgs.python3.withPackages (p: [
    p.mcp
    p.httpx
    p.anyio
  ]);

  # The session and its housekeeping use the shimmers -> Runpod route. The MCP worker makes
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
        name = "shimmers → Runpod GPU (paid)";
        package = "@opencode/ai/providers/openai-compatible";
        settings = {
          baseURL = "http://127.0.0.1:18091/v1";
          # The first request copies the existing GGUF to a fresh Pod.
          headerTimeout = 1860000;
          # Keep-alive prompts must not wake another paid Pod after idle cleanup.
          cache.warming = false;
        };
        headers."X-Shimmers-GPU-Review" = "1";
        models."qwen3.6-35b-a3b-uncensored" = {
          name = "Qwen3.6 35B-A3B Uncensored · Runpod GPU (paid)";
          capabilities = {
            tools = true;
            input = [ "text" ];
            output = [ "text" ];
            reasoning.supported = true;
          };
          compatibility.reasoningField = "reasoning_content";
          limit = {
            context = 65536;
            output = 4096;
          };
          variants = [
            {
              id = "instant";
              body.chat_template_kwargs.enable_thinking = false;
            }
            {
              id = "thinking";
              body.chat_template_kwargs.enable_thinking = true;
            }
          ];
        };
      };

      agents.redteam = {
        description = "Security work with Qwen3.6 hosted on an on-demand Runpod GPU";
        mode = "primary";
        model = llmModel;
        color = "#d14b4b";
      };
    };
  };

  home.file."redteam/opencode.json".text = builtins.toJSON (
    docsWorkspace // { default_agent = "redteam"; }
  );

  # The GPU workspace now has the same agent/tool capabilities as ~/redteam.
  home.file."gpu-review/opencode.json".text = builtins.toJSON (
    docsWorkspace // { default_agent = "redteam"; }
  );

  home.packages = [
    (pkgs.writeShellScriptBin "gpu-review-prepare" ''
      exec ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=yes aleph@shimme.rs \
        'sudo systemctl start runpod-review-weights && sudo systemctl start runpod-review'
    '')
    (pkgs.writeShellScriptBin "gpu-review" ''
      set -eu
      ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=yes aleph@shimme.rs \
        'sudo systemctl start runpod-review && sudo systemctl start runpod-review-resume'
      ${pkgs.systemd}/bin/systemctl --user restart runpod-review-tunnel
      printf '%s\n' 'GPU: your first prompt starts a paid Pod (A5000 preferred, A40 fallback). Run gpu-review-stop for immediate release.' >&2
      exec ${config.programs.opencode.package}/bin/opencode ${lib.escapeShellArg "${config.home.homeDirectory}/gpu-review"} "$@"
    '')
    (pkgs.writeShellScriptBin "gpu-review-resume" ''
      set -eu
      ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=yes aleph@shimme.rs \
        'sudo systemctl start runpod-review && sudo systemctl start runpod-review-resume'
      ${pkgs.systemd}/bin/systemctl --user start runpod-review-tunnel
    '')
    (pkgs.writeShellScriptBin "gpu-review-stop" ''
      set -eu
      ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=yes aleph@shimme.rs \
        'sudo systemctl start runpod-review-pause && sudo runpod-review-status'
    '')
    (pkgs.writeShellScriptBin "gpu-review-status" ''
      exec ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=yes aleph@shimme.rs \
        'sudo runpod-review-status'
    '')
  ];

  # Always available to regular OpenCode. The tunnel cannot start a Pod and stays
  # up during an explicit pause so callers get a non-retryable 403, not a retry loop.
  systemd.user.services.runpod-review-tunnel = {
    Unit.Description = "Forward the shimmers GPU review socket";
    Service = {
      ExecStart = "${pkgs.openssh}/bin/ssh -NT -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=yes -L 127.0.0.1:18091:/run/runpod-review/chat.sock aleph@shimme.rs";
      Restart = "always";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };

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

}
