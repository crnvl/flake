{ pkgs, ... }:

{
  services.kanidm = {
    package = pkgs.kanidm_1_9;

    server = {
      enable = true;
      settings = {
        origin = "https://id.shimme.rs";
        domain = "id.shimme.rs";
        bindaddress = "127.0.0.1:8443";
        tls_chain = "/var/lib/acme/id.shimme.rs/fullchain.pem";
        tls_key = "/var/lib/acme/id.shimme.rs/key.pem";
      };
    };
  };

  security.acme.certs."id.shimme.rs" = {
    group = "acme";
    reloadServices = [
      "kanidm"
      "nginx"
    ];
  };

  users.users = {
    kanidm.extraGroups = [ "acme" ];
  };

  services.nginx.virtualHosts."id.shimme.rs" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "https://127.0.0.1:8443";
      proxyWebsockets = true;
    };
  };
}
