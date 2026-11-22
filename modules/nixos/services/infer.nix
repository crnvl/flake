{ config, ... }:

# On-demand GPU inference for shimme.rs members (https://git.gay/67/infer).
# Who may sign in is the infer_users group in kanidm.nix; infer_admins get the
# admin page. Replaces the personal runpod-review gateway: on first start it
# adopts that state file (any live Pod, its cleanup tokens, the month's budget).
{
  age.secrets.kanidm-oauth2-infer-secret = {
    file = ../../../hosts/shimmers/secrets/kanidm-oauth2-infer-secret.age;
    owner = "kanidm";
    group = "kanidm";
  };

  services.infer = {
    enable = true;
    domain = "infer.shimme.rs";
    oidc = {
      issuer = "https://id.shimme.rs/oauth2/openid/infer";
      # Read via LoadCredential (as root), so kanidm's copy is shared.
      clientSecretFile = config.age.secrets.kanidm-oauth2-infer-secret.path;
    };
    # Root-only file placed by hand; never reaches users or Pods.
    runpodKeyFile = "/etc/runpod-review/api-key";
    # The Qwen3.6 GGUF downloaded earlier for CPU inference; no re-download.
    modelDir = "/var/lib/llm/models";
    importState = "/var/lib/runpod-review/state.json";
    monthlyGpuHours = 6;
    defaultUserMinutes = 60;
  };

  systemd.services.infer = {
    after = [ "kanidm.service" ];
    wants = [ "kanidm.service" ];
  };
}
