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
    # Friends prepay: admins grant hours on the portal (1 € = 1.5 h by default,
    # adjustable there). No free monthly minutes; admins are not limited.
    # 50 GPU-hours/month (≈ €27 at A40 prices) is a safety ceiling that admins
    # can lower in the portal but not raise.
    monthlyGpuHours = 50;
    defaultUserMinutes = 0;
    hoursPerEuro = 1.5;
  };

  systemd.services.infer = {
    after = [ "kanidm.service" ];
    wants = [ "kanidm.service" ];
  };
}
