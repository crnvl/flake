{ config, ... }:

{
  age.secrets.kanidm-oauth2-catshift-secret = {
    file = ../../../hosts/shimmers/secrets/kanidm-oauth2-catshift-secret.age;
    owner = "kanidm";
    group = "kanidm";
  };

  services.catshift = {
    enable = true;
    port = 3080;
    domain = "shift.shimme.rs";
    oidc = {
      issuerUrl = "https://id.shimme.rs/oauth2/openid/catshift";
      clientSecretFile = config.age.secrets.kanidm-oauth2-catshift-secret.path;
    };
    kanidm.provision = true;
  };

  services.nginx.virtualHosts."shift.shimme.rs" = {
    forceSSL = true;
    enableACME = true;
    locations."/".proxyPass = "http://127.0.0.1:3080";
  };
}
