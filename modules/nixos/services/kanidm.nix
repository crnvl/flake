{ ... }:

{
  services.kanidm = {
    enableServer = true;
    serverSettings = {
      origin = "https://id.shimme.rs";
      domain = "id.shimme.rs";
      bindaddress = "127.0.0.1:8443";
      tls_chain = "/var/lib/acme/id.shimme.rs/fullchain.pem";
      tls_key = "/var/lib/acme/id.shimme.rs/key.pem";
    };
  };

  security.acme.certs."id.shimme.rs" = {
    group = "kanidm";
    reloadServices = [ "kanidm" ];
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
