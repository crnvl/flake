{ config, ... }:

{
  age.secrets.kanidm-oauth2-catshift-secret = {
    file = ../../../hosts/shimmers/secrets/kanidm-oauth2-catshift-secret.age;
    owner = "kanidm";
    group = "kanidm";
  };

  age.secrets.catshift-oidc-secret = {
    file = ../../../hosts/shimmers/secrets/kanidm-oauth2-catshift-secret.age;
    owner = "catshift";
    group = "catshift";
  };

  services.catshift = {
    enable = true;
    listenAddr = "127.0.0.1:3080";
    domain = "shift.shimme.rs";
    oidc = {
      issuerUrl = "https://id.shimme.rs/oauth2/openid/catshift";
      clientId = "catshift";
      clientSecretFile = config.age.secrets.catshift-oidc-secret.path;
    };
  };

  services.nginx.virtualHosts."shift.shimme.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/".proxyPass = "http://127.0.0.1:3080";
  };
}
