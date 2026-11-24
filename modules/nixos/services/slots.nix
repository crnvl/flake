{ config, mkProxyHost, ... }:

# Play-money slot machines for friends (https://git.gay/67/gambling).
# Who may sign in is the slots_users group in kanidm.nix.
{
  age.secrets.kanidm-oauth2-slots-secret = {
    file = ../../../hosts/shimmers/secrets/kanidm-oauth2-slots-secret.age;
    owner = "kanidm";
    group = "kanidm";
  };

  # The Discord webhook slots announces big wins and leaderboard changes to.
  # Read via LoadCredential (as root), like the client secret.
  age.secrets.slots-discord-webhook.file = ../../../hosts/shimmers/secrets/slots-discord-webhook.age;

  services.slots = {
    enable = true;
    domain = "slots.shimme.rs";
    listenAddr = "127.0.0.1:3085";
    oidc = {
      issuer = "https://id.shimme.rs/oauth2/openid/slots";
      # Read via LoadCredential (as root), so kanidm's copy is shared.
      clientSecretFile = config.age.secrets.kanidm-oauth2-slots-secret.path;
    };
    discord.webhookFile = config.age.secrets.slots-discord-webhook.path;
  };

  # The live feed is a long-lived event stream; the app tells nginx not to
  # buffer it and sends a keep-alive well inside the proxy timeout.
  services.nginx.virtualHosts."slots.shimme.rs" = mkProxyHost {
    port = 3085;
    websockets = false;
  };

  systemd.services.slots = {
    after = [ "kanidm.service" ];
    wants = [ "kanidm.service" ];
  };
}
