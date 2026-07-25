{ config, pkgs, inputs, mkProxyHost, ... }:

let
  domain = "vitals.shimme.rs";
in
{
  age.secrets = {
    beat-env = {
      file = ../../../hosts/shimmers/secrets/beat-env.age;
      owner = "beat";
      group = "beat";
    };
  };


  users.users.beat = {
    isSystemUser = true;
    group = "beat";
  };
  users.groups.beat = { };

  systemd.services.beat = {
    description = "beat - Oura vitals dashboard";
    after = [
      "network-online.target"
      "kanidm.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      BEAT_LISTEN_ADDR = "127.0.0.1:3081";
      OIDC_ISSUER = "https://id.shimme.rs/oauth2/openid/beat";
      OIDC_CLIENT_ID = "beat";
      OIDC_REDIRECT_URL = "https://${domain}/auth/callback";
    };

    serviceConfig = {
      ExecStart = "${inputs.beat.packages.${pkgs.system}.default}/bin/beat";
      EnvironmentFile = [ config.age.secrets.beat-env.path ];

      User = "beat";
      Group = "beat";
      Restart = "on-failure";
      RestartSec = "5s";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };

  services.nginx.virtualHosts.${domain} = mkProxyHost {
    port = 3081;
    websockets = false;
  };
}
