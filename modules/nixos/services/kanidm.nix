{
  pkgs,
  config,
  lib,
  mkProxyHost,
  ...
}:

let
  # Extra links for the signed-in navbar (see the id.shimme.rs vhost below).
  # They end up inside a single-quoted nginx string, so no single quotes.
  navbarLinks =
    ''<ul class="navbar-nav">''
    +
      lib.concatMapStrings
        (
          link:
          ''<li><a class="nav-link" href="${link.url}" target="_blank" rel="noopener noreferrer">${link.label}</a></li>''
        )
        [
          {
            label = "Status";
            url = "https://status.shimme.rs";
          }
          {
            label = "Discord";
            url = "https://discord.gg/A5bE2Ffzwn";
          }
        ]
    + "</ul>";

  # People who should not get slots.shimme.rs (see the slots_users group).
  slotsExcluded = [ ];
in
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
    package = pkgs.kanidm_1_12.withSecretProvisioning;

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
        # infer.shimme.rs: members may sign in and get API keys (they spend
        # the shared Runpod allowance); admins also get the admin page.
        infer_users = { };
        infer_admins = { };
        # slots.shimme.rs: play-money slot machines. Everyone with an account
        # may play; list a name in slotsExcluded above to leave them out.
        slots_users.members = lib.subtractLists slotsExcluded (
          lib.attrNames config.services.kanidm.provision.persons
        );
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
            "infer_users"
            "infer_admins"
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
            "aurral_users"
            "navidrome_users"
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
            "aurral_users"
            "navidrome_users"
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
            "aurral_users"
            "navidrome_users"
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

        petra = {
          displayName = "petra";
          mailAddresses = [ "petra@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };

        azur = {
          displayName = "azur";
          mailAddresses = [ "azur@shimme.rs" ];
          groups = [
            "jellyfin_users"
            "aurral_users"
            "navidrome_users"
            "infer_users"
          ];
        };

        ellie = {
          displayName = "ellie";
          mailAddresses = [ "ellie@shimme.rs" ];
          groups = [
            "jellyfin_users"
          ];
        };
      };

      # Icons shown in the Kanidm app list; see ./kanidm-logos.
      systems.oauth2 = {
        jellyfin = {
          displayName = "jellyfin";
          imageFile = ./kanidm-logos/jellyfin.svg;
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
          imageFile = ./kanidm-logos/catshift.svg;
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
          imageFile = ./kanidm-logos/vaultwarden.svg;
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

        nextcloud = lib.mkIf config.services.nextcloud.enable {
          displayName = "nextcloud";
          imageFile = ./kanidm-logos/nextcloud.svg;
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
          imageFile = ./kanidm-logos/aurral.svg;
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
          imageFile = ./kanidm-logos/navidrome.svg;
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

        # infer (modules/nixos/services/infer.nix) sends an S256 PKCE
        # challenge, so PKCE stays enforced. Members of infer_users can sign
        # in; infer_admins additionally get infer_role = ["admin"].
        infer = {
          displayName = "infer";
          imageFile = ./kanidm-logos/infer.svg;
          originUrl = "https://infer.shimme.rs/auth/callback";
          originLanding = "https://infer.shimme.rs";
          basicSecretFile = config.age.secrets.kanidm-oauth2-infer-secret.path;
          preferShortUsername = true;

          scopeMaps.infer_users = [
            "openid"
            "profile"
            "email"
          ];

          claimMaps.infer_role = {
            joinType = "array";
            valuesByGroup.infer_admins = [ "admin" ];
          };
        };

        # slots (modules/nixos/services/slots.nix) sends an S256 PKCE
        # challenge, so PKCE stays enforced. It only asks for a name.
        slots = {
          displayName = "slots";
          imageFile = ./kanidm-logos/slots.svg;
          originUrl = "https://slots.shimme.rs/auth/callback";
          originLanding = "https://slots.shimme.rs";
          basicSecretFile = config.age.secrets.kanidm-oauth2-slots-secret.path;
          preferShortUsername = true;

          scopeMaps.slots_users = [
            "openid"
            "profile"
          ];
        };

        # Forgejo on git.lily.pizza, auth source named "shimmers". Forgejo
        # sends an S256 PKCE challenge for OpenID Connect sources, so PKCE
        # stays enforced.
        lily_git = {
          displayName = "git.lily.pizza";
          imageFile = ./kanidm-logos/forgejo.svg;
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

  environment.systemPackages = [ pkgs.kanidm_1_12 ];

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
      # Extra links in the navbar, which only signed-in pages have (with the
      # aero theme it is the taskbar). Kanidm's templates are compiled in, so
      # nginx adds them on the way through, just before the "Sign out" list.
      # sub_filter only sees uncompressed responses, so ask kanidm for those;
      # nginx compresses again towards the browser.
      locationExtraConfig = ''
        proxy_set_header Accept-Encoding "";
        sub_filter_once on;
        sub_filter '<ul class="navbar-nav ms-md-auto">' '${navbarLinks}<ul class="navbar-nav ms-md-auto">';
      '';
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
