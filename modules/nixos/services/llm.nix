{ pkgs, ... }:

# Keep the existing Qwen3.6 GGUF on Hetzner. Inference now runs in the
# on-demand GPU Pod controlled by services/runpod-review, not on this CPU.
let
  model = builtins.fromJSON (builtins.readFile ./runpod-review/model.json);
in
{
  systemd.services.llm-model-fetch = {
    description = "Cache pinned Qwen3.6 weights for Runpod inference";
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
      dest=/var/lib/llm/models/${model.file}
      [ -e "$dest" ] && exit 0
      curl --fail --location --retry 5 --continue-at - --output "$dest.part" \
        "https://huggingface.co/${model.repo}/resolve/${model.revision}/${model.file}"
      if ! echo "${model.sha256}  $dest.part" | sha256sum --check --quiet; then
        rm -f "$dest.part"
        exit 1
      fi
      chmod 0444 "$dest.part"
      mv "$dest.part" "$dest"
    '';
  };
}
