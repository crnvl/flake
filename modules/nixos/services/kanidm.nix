{ pkgs, config, ... }:

{
  age.secrets.kanidm-idm-admin-password = {
    file = ../../../hosts/shimmers/secrets/kanidm-idm-admin-password.age;
    owner = "kanidm";
    group = "kanidm";
  };
  age.secrets.kanidm-admin-password = {
    file = ../../../hosts/shimmers/secrets/kanidm-admin-password.age;
    owner = "kanidm";
    group = "kanidm";
  };
  age.secrets.kanidm-oauth2-jellyfin-secret = {
    file = ../../../hosts/shimmers/secrets/kanidm-oauth2-jellyfin-secret.age;
    owner = "kanidm";
    group = "kanidm";
  };

  services.kanidm = {
    package = pkgs.kanidm_1_9.withSecretProvisioning;

    client = {
      enable = true;
      settings.uri = "https://id.shimme.rs";
    };

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

      idmAdminPasswordFile = config.age.secrets.kanidm-idm-admin-password.path;
      adminPasswordFile = config.age.secrets.kanidm-admin-password.path;

      groups = {
        jellyfin_users = { };
        seerr_users = { };
      };

      # create creds: sudo kanidm person credential create-reset-token aleph
      persons = {
        aleph = {
          displayName = "aleph";
          mailAddresses = [ "aleph@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };

        jil = {
          displayName = "jil";
          mailAddresses = [ "jil@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };

        klyk = {
          displayName = "klyk";
          mailAddresses = [ "klyk@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };

        megu = {
          displayName = "megu";
          mailAddresses = [ "megu@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };

        zeldafangirl = {
          displayName = "zeldafangirl";
          mailAddresses = [ "zeldafangirl@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };
      };

      systems.oauth2 = {
        jellyfin = {
          displayName = "jellyfin";
          originUrl = [
            "https://jellyfin.shimme.rs"
            "https://jellyfin.shimme.rs/sso/OID/redirect/kanidm"
            "https://jellyfin.shimme.rs/sso/OID/r/kanidm"
          ];
          originLanding = "https://jellyfin.shimme.rs";
          basicSecretFile = config.age.secrets.kanidm-oauth2-jellyfin-secret.path;
          allowInsecureClientDisablePkce = true;
          preferShortUsername = true;

          scopeMaps.jellyfin_users = [
            "openid"
            "profile"
            "email"
            "groups"
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

  systemd.services.kanidm.serviceConfig.BindReadOnlyPaths = [
    "/var/lib/acme/id.shimme.rs/"
  ];

  services.nginx.virtualHosts."id.shimme.rs" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "https://127.0.0.1:8443";
      proxyWebsockets = true;
    };
  };
}
