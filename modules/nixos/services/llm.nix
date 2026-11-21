{ lib, pkgs, ... }:

# Self-hosted LLM for OpenCode on the desktops (see modules/home/opencode.nix),
# running CPU-only on the EPYC Genoa cores. llama.cpp's dynamic CPU dispatch
# picks its zen4 (AVX-512/VNNI/BF16) backend at runtime.
#
# llama-swap starts llama-server on the first request and stops it again
# after `ttl` idle seconds, so the ~19 GiB of weights and cache are only
# resident while the model is in use. It only listens on localhost; the
# desktops reach it through an SSH tunnel, so nothing is exposed publicly.
let
  port = 8090;
  modelDir = "/var/lib/llm/models";

  # Qwen3.6-35B-A3B with refusals removed (HauhauCS "Aggressive"). A MoE with
  # ~3B active parameters per token, which keeps it usable on CPU; hybrid
  # attention keeps the KV cache for 128k context around 1.3 GiB at q8_0.
  # Pinned to a repo revision and checked against the LFS sha256.
  model = {
    id = "qwen3.6-35b-a3b-uncensored";
    repo = "HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive";
    rev = "f12a584fecbeb5f20001130d8ecd66c9327ae685";
    file = "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_XS.gguf";
    sha256 = "c26708a77a26d6c0416502832a200de4135e91af8279b5e93c67fe4e4e081aae";
  };

  llama-server = lib.getExe' pkgs.llama-cpp "llama-server";
in
{
  # The weights are too big for the nix store; fetch them once into
  # /var/lib/llm/models. Not a oneshot, so a switch doesn't block on the
  # ~19 GB download.
  systemd.services.llm-model-fetch = {
    description = "Download the LLM weights served by llama-swap";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.curl
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "simple";
      StateDirectory = "llm/models";
      Restart = "on-failure";
      RestartSec = 60;
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    script = ''
      dest=${modelDir}/${model.file}
      [ -e "$dest" ] && exit 0
      curl --fail --location --retry 5 --continue-at - --output "$dest.part" \
        "https://huggingface.co/${model.repo}/resolve/${model.rev}/${model.file}"
      if ! echo "${model.sha256}  $dest.part" | sha256sum --check --quiet; then
        rm -f "$dest.part"
        exit 1
      fi
      mv "$dest.part" "$dest"
    '';
  };

  services.llama-swap = {
    enable = true;
    listenAddress = "127.0.0.1";
    inherit port;
    settings = {
      # Loading 19 GB from disk after an unload takes a while.
      healthCheckTimeout = 600;
      # Don't keep copies of prompts and responses around for the web UI.
      captureBuffer = 0;

      models.${model.id} = {
        name = "Qwen3.6 35B-A3B Uncensored";
        ttl = 900;
        cmd = lib.concatStringsSep " " [
          llama-server
          "--host 127.0.0.1 --port \${PORT}"
          "--model ${modelDir}/${model.file}"
          "--no-ui"
          # 12 of the 16 cores; the rest stay with the other services.
          "--threads 12 --threads-batch 12"
          # One slot with the full 128k context (Qwen's minimum for
          # thinking), quantized KV cache.
          "--parallel 1 --ctx-size 131072"
          "--flash-attn on --cache-type-k q8_0 --cache-type-v q8_0"
          # Defaults are 8 GiB of prompt cache and 32 recurrent-state
          # checkpoints, which this box can't spare.
          "--cache-ram 1024 --ctx-checkpoints 8"
          "--jinja"
          # Qwen's recommended sampling for coding in thinking mode.
          "--temp 0.6 --top-p 0.95 --top-k 20 --min-p 0"
        ];
      };
    };
  };

  # llama-server runs inside this unit's cgroup. Cap it so it can never push
  # out kanidm/vaultwarden/mail, and make it the first thing the OOM killer
  # picks.
  systemd.services.llama-swap.serviceConfig = {
    MemoryMax = "22G";
    OOMScoreAdjust = 900;
    Nice = 10;
    CPUWeight = 20;
    IOWeight = 20;
  };
}
