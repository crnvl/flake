{
  pkgs,
  config,
  lib,
  mkProxyHost,
  ...
}:

{
  age.secrets =
    lib.genAttrs
      [
        "kanidm-idm-admin-password"
        "kanidm-admin-password"
        "kanidm-oauth2-jellyfin-secret"
        "kanidm-oauth2-vaultwarden-secret"
        "kanidm-oauth2-lily-git-secret"
      ]
      (name: {
        file = ../../../hosts/shimmers/secrets/${name}.age;
        owner = "kanidm";
        group = "kanidm";
      });

  services.kanidm = {
    package = pkgs.kanidm_1_11.withSecretProvisioning;

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

        # The upstream module sets this to a derivation, which its
        # filterAttrsRecursive then walks into, triggering the
        # `stdenv.is*` deprecation warnings. Same path, but as a string.
        migration_path = lib.mkForce (
          toString (
            pkgs.linkFarm "kanidm-entry-management" (
              lib.mapAttrsToList (name: value: {
                name = "${name}.json";
                path = (pkgs.formats.json { }).generate "${name}.json" value;
              }) config.services.kanidm.server.entryManagement.migrations
            )
          )
        );
      };
    };

    provision = {
      enable = true;

      idmAdminPasswordFile = config.age.secrets.kanidm-idm-admin-password.path;
      adminPasswordFile = config.age.secrets.kanidm-admin-password.path;

      groups = {
        jellyfin_users = { };
        jellyfin_admins = { };
        seerr_users = { };
        catshift_users = { };
        vaultwarden_users = { };
        nextcloud_users = { };
        nextcloud_admins = { };
        lily_git_users = { };
        aurral_users = { };
        navidrome_users = { };
      };

      # create creds: sudo kanidm person credential create-reset-token aleph
      persons = {
        aleph = {
          displayName = "aleph";
          mailAddresses = [ "aleph@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "jellyfin_admins"
            "catshift_users"
            "vaultwarden_users"
            "nextcloud_users"
            "nextcloud_admins"
            "lily_git_users"
            "aurral_users"
            "navidrome_users"
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
            "catshift_users"
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
            "catshift_users"
          ];
        };

        dwcs = {
          displayName = "dwcs";
          mailAddresses = [ "dwcs@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "catshift_users"
          ];
        };

        liegfra = {
          displayName = "liegfra";
          mailAddresses = [ "liegfra@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "catshift_users"
          ];
        };

        judi = {
          displayName = "judi";
          mailAddresses = [ "judi@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "catshift_users"
          ];
        };

        feinwaage = {
          displayName = "feinwaage";
          mailAddresses = [ "feinwaage@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "nextcloud_users"
            "vaultwarden_users"
          ];
        };

        hurensohn = {
          displayName = "hurensohn";
          mailAddresses = [ "hurensohn@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };

        conny = {
          displayName = "conny";
          mailAddresses = [ "conny@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "vaultwarden_users"
          ];
        };

        blu = {
          displayName = "blu";
          mailAddresses = [ "blu@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };

        nobelboje = {
          displayName = "nobelboje";
          mailAddresses = [ "nobelboje@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };

        konkurs = {
          displayName = "konkurs";
          mailAddresses = [ "konkurs@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };

        lyssenka = {
          displayName = "lyssenka";
          mailAddresses = [ "lyssenka@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "nextcloud_users"
          ];
        };

        masha = {
          displayName = "masha";
          mailAddresses = [ "masha@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "nextcloud_users"
            "vaultwarden_users"
          ];
        };

        lily = {
          displayName = "lily";
          mailAddresses = [ "lily@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "nextcloud_users"
          ];
        };

        yannick = {
          displayName = "yannick";
          mailAddresses = [ "yannick@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "vaultwarden_users"
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

          claimMaps.jellyfin_role = {
            joinType = "array";
            valuesByGroup.jellyfin_admins = [ "admin" ];
          };
        };

        catshift = {
          displayName = "catshift";
          originUrl = "https://shift.shimme.rs/auth/callback";
          originLanding = "https://shift.shimme.rs";
          basicSecretFile = config.age.secrets.kanidm-oauth2-catshift-secret.path;
          allowInsecureClientDisablePkce = true;
          preferShortUsername = true;

          scopeMaps.catshift_users = [
            "openid"
            "profile"
            "email"
          ];
        };

        vaultwarden = {
          displayName = "vaultwarden";
          originUrl = "https://vault.shimme.rs/identity/connect/oidc-signin";
          originLanding = "https://vault.shimme.rs";
          basicSecretFile = config.age.secrets.kanidm-oauth2-vaultwarden-secret.path;
          preferShortUsername = true;
          scopeMaps.vaultwarden_users = [
            "openid"
            "profile"
            "email"
          ];
        };

        nextcloud = {
          displayName = "nextcloud";
          originUrl = "https://cloud.shimme.rs/apps/user_oidc/code";
          originLanding = "https://cloud.shimme.rs";
          basicSecretFile = config.age.secrets.kanidm-oauth2-nextcloud-secret.path;
          preferShortUsername = true;

          scopeMaps.nextcloud_users = [
            "openid"
            "profile"
            "email"
          ];

          claimMaps.nextcloud_groups = {
            joinType = "array";
            valuesByGroup.nextcloud_admins = [ "admin" ];
          };
        };

        # Aurral sends an S256 PKCE challenge, so PKCE stays enforced.
        aurral = {
          displayName = "aurral";
          originUrl = "https://aurral.shimme.rs/sso/callback";
          originLanding = "https://aurral.shimme.rs";
          basicSecretFile = config.age.secrets.kanidm-oauth2-aurral-secret.path;
          preferShortUsername = true;

          scopeMaps.aurral_users = [
            "openid"
            "profile"
            "email"
          ];
        };

        # oauth2-proxy in front of navidrome (see navidrome.nix), with S256
        # PKCE.
        navidrome = {
          displayName = "navidrome";
          originUrl = "https://music.shimme.rs/oauth2/callback";
          originLanding = "https://music.shimme.rs";
          basicSecretFile = config.age.secrets.kanidm-oauth2-navidrome-secret.path;
          preferShortUsername = true;

          scopeMaps.navidrome_users = [
            "openid"
            "profile"
            "email"
          ];
        };

        # Forgejo on git.lily.pizza, auth source named "shimmers". Forgejo
        # sends an S256 PKCE challenge for OpenID Connect sources, so PKCE
        # stays enforced.
        lily_git = {
          displayName = "git.lily.pizza";
          originUrl = "https://git.lily.pizza/user/oauth2/shimmers/callback";
          originLanding = "https://git.lily.pizza";
          basicSecretFile = config.age.secrets.kanidm-oauth2-lily-git-secret.path;
          preferShortUsername = true;

          scopeMaps.lily_git_users = [
            "openid"
            "profile"
            "email"
          ];
        };
      };
    };
  };

  environment.systemPackages = [ pkgs.kanidm_1_11 ];

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

  services.nginx.virtualHosts."id.shimme.rs" = lib.mkMerge [
    (mkProxyHost {
      port = 8443;
      scheme = "https";
    })
    {
      # Kanidm's base template loads /pkg/override.css after its own
      # styles as a custom-theming hook; the file it ships is empty.
      # Serving ours, and the images it uses under /pkg/aero/, from nginx
      # avoids rebuilding kanidm. (?v= cache busters are query strings,
      # which location matching ignores.)
      locations."= /pkg/override.css".alias = "${./kanidm-aero}/override.css";
      locations."^~ /pkg/aero/".alias = "${./kanidm-aero}/";
    }
  ];
}
