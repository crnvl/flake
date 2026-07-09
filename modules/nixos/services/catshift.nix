{ config, mkProxyHost, ... }:

{
  age.secrets.kanidm-oauth2-catshift-secret = {
    file = ../../../hosts/shimmers/secrets/kanidm-oauth2-catshift-secret.age;
    owner = "kanidm";
    group = "kanidm";
    mode = "0440";
  };

  users.users.catshift.extraGroups = [ "kanidm" ];

  services.catshift = {
    enable = true;
    listenAddr = "127.0.0.1:3080";
    domain = "shift.shimme.rs";
    oidc = {
      issuerUrl = "https://id.shimme.rs/oauth2/openid/catshift";
      clientId = "catshift";
      clientSecretFile = config.age.secrets.kanidm-oauth2-catshift-secret.path;
    };
    adminUsers = [ "aleph" ];
  };

  services.nginx.virtualHosts."shift.shimme.rs" = mkProxyHost {
    port = 3080;
    websockets = false;
  };

  systemd.services.catshift = {
    after = [ "kanidm.service" ];
    requires = [ "kanidm.service" ];
  };
}
