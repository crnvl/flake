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

    provision = {
      enable = true;

      groups.jellyfin_users = { };

      persons = {
        aleph = {
          displayName = "aleph";
          mailAddresses = [ "aleph@shimme.rs" ];
          groups = [ "jellyfin_users" ];
        };
      };

      systems.oauth2 = {
        jellyfin = {
          displayName = "jellyfin";
          originUrl = "https://jellyfin.shimme.rs";
          originLanding = "https://jellyfin.shimme.rs";
          scopeMaps.jellyfin_users = [
            "openid"
            "profile"
            "email"
          ];
        };
      };
    };
  };

  environment.systemPackages = [ pkgs.kanidm_1_9 ];

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
