{
  config,
  lib,
  pkgs,
  ...
}:

let
  domain = "cloud.shimme.rs";
  occ = lib.getExe config.services.nextcloud.occ;
  apps = config.services.nextcloud.package.packages.apps;

  # nixpkgs only packages recognize up to NC34. v13.1.0 supports NC35/36.
  # Drop this once nixpkgs has a "35" entry in apps/recognize.nix.
  recognize = apps.recognize.overrideAttrs (
    finalAttrs: old: {
      version = "13.1.0";

      srcs = [
        (pkgs.fetchurl {
          url = "https://github.com/nextcloud/recognize/releases/download/v${finalAttrs.version}/recognize-${finalAttrs.version}.tar.gz";
          hash = "sha256-bdeMFBomHKbEZC/lL7TBl5nFB5PGRtay5TaWwvwHo7E=";
        })
        (pkgs.fetchurl {
          url = "https://github.com/nextcloud/recognize/archive/refs/tags/v${finalAttrs.version}.tar.gz";
          hash = "sha256-WTiWOpEHD6+RfI2iGt+jBmoawaJOCDn2Ov49zX9yaJA=";
        })
      ]
      # libtensorflow (unchanged, still 2.9.1)
      ++ lib.drop 2 old.srcs;

      unpackPhase = ''
        tar -xzpf "${builtins.elemAt finalAttrs.srcs 0}" recognize
        tar -xzpf "${builtins.elemAt finalAttrs.srcs 1}" -C recognize --strip-components=1 recognize-${finalAttrs.version}/models
      ''
      + lib.optionalString (lib.length finalAttrs.srcs > 2) ''
        tar -xzpf "${builtins.elemAt finalAttrs.srcs 2}" -C recognize/node_modules/@tensorflow/tfjs-node/deps
      '';

      meta = old.meta // {
        changelog = "https://github.com/nextcloud/recognize/blob/v${finalAttrs.version}/CHANGELOG.md";
      };
    }
  );
in
{
  age.secrets = {
    # Password of the local "admin" account the original install created.
    # nixpkgs no longer takes it as config (new installs skip the admin user),
    # so nothing reads this; it stays decrypted as the break-glass login for
    # when OIDC is down.
    nextcloud-admin-password = {
      file = ../../../hosts/shimmers/secrets/nextcloud-admin-password.age;
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };

    kanidm-oauth2-nextcloud-secret = {
      file = ../../../hosts/shimmers/secrets/kanidm-oauth2-nextcloud-secret.age;
      owner = "kanidm";
      group = "kanidm";
      mode = "0440";
    };
  };

  services.nextcloud = {
    enable = false;
    package = pkgs.nextcloud35;
    hostName = domain;
    https = true;

    maxUploadSize = "16G";
    configureRedis = true;
    database.createLocally = true;

    appstoreEnable = false;

    config = {
      dbtype = "pgsql";
    };

    extraApps = {
      inherit (apps)
        user_oidc
        calendar
        contacts
        maps
        previewgenerator
        ;
      inherit recognize;
    };

    imaginary.enable = true;

    settings = {
      default_phone_region = "DE";
      overwriteprotocol = "https";
      "overwrite.cli.url" = "https://${domain}";
      log_type = "file";
      loglevel = 2;
      maintenance_window_start = 1;

      enabledPreviewProviders = lib.mkForce [
        "OC\\Preview\\Imaginary"
        "OC\\Preview\\ImaginaryPDF"
        "OC\\Preview\\Movie"
        "OC\\Preview\\Krita"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\TXT"
        "OC\\Preview\\OpenDocument"
      ];
      preview_ffmpeg_path = lib.getExe pkgs.ffmpeg-headless;

      preview_max_x = 2048;
      preview_max_y = 2048;
      jpeg_quality = 60;
    };

    phpOptions = {
      memory_limit = lib.mkForce "1G";
      "opcache.interned_strings_buffer" = "32";
    };

    cli.memoryLimit = "2G";

    notify_push = {
      enable = true;
      bendDomainToLocalhost = true;
    };
  };

  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    forceSSL = true;

    extraConfig = ''
      access_log syslog:server=unix:/dev/log,tag=nginx_nextcloud timed;
    '';
  };

  systemd.services.nextcloud-settings = {
    description = "Apply declarative Nextcloud settings";
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-setup.service" ];
    requires = [ "nextcloud-setup.service" ];

    script = ''
      ${occ} app:disable activity office notes tasks

      ${occ} config:app:set recognize imagenet.enabled --value=true
      ${occ} config:app:set recognize faces.enabled --value=true
      ${occ} config:app:set recognize landmarks.enabled --value=true

      ${occ} config:app:set recognize movinet.enabled --value=false
      ${occ} config:app:set recognize musicnn.enabled --value=false
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "nextcloud";
      Group = "nextcloud";
    };
  };

  systemd.services.nextcloud-oidc-setup = {
    description = "Provision the kanidm OIDC provider in Nextcloud";
    wantedBy = [ "multi-user.target" ];
    after = [
      "nextcloud-setup.service"
      "phpfpm-nextcloud.service"
      "kanidm.service"
    ];
    requires = [ "nextcloud-setup.service" ];

    script = ''
      ${occ} app:enable user_oidc

      ${occ} user_oidc:provider kanidm \
        --clientid="nextcloud" \
        --clientsecret-file="$CREDENTIALS_DIRECTORY/oidc-secret" \
        --discoveryuri="https://id.shimme.rs/oauth2/openid/nextcloud/.well-known/openid-configuration" \
        --scope="openid profile email" \
        --unique-uid=0 \
        --check-bearer=0 \
        --mapping-uid="preferred_username" \
        --mapping-display-name="name" \
        --mapping-email="email" \
        --group-provisioning=1 \
        --mapping-groups="nextcloud_groups" \
        --group-whitelist-regex='^admin$'

      ${occ} config:app:set user_oidc allow_multiple_user_backends --value=1
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "nextcloud";
      Group = "nextcloud";
      LoadCredential = [
        "oidc-secret:${config.age.secrets.kanidm-oauth2-nextcloud-secret.path}"
      ];
      RestartMode = "direct";
      Restart = "on-failure";
      RestartSec = "10s";
    };

    unitConfig = {
      StartLimitIntervalSec = 120;
      StartLimitBurst = 5;
    };
  };

  systemd.services.nextcloud-photo-reindex = {
    description = "Re-scan and re-index the photo library";
    after = [
      "nextcloud-setup.service"
      "phpfpm-nextcloud.service"
    ];
    requires = [ "nextcloud-setup.service" ];

    script = ''
      echo ">>> [1/5] files:scan"
      ${occ} --no-interaction files:scan --all --generate-metadata

      echo ">>> [2/5] photos:update-1000-cities"
      ${occ} --no-interaction photos:update-1000-cities

      echo ">>> [3/5] recognize:classify"
      # Skips files already carrying the processed tag.
      ${occ} --no-interaction recognize:classify

      echo ">>> [4/5] recognize:cluster-faces"
      ${occ} --no-interaction recognize:cluster-faces

      echo ">>> [5/5] preview:generate-all"
      # Skips files that already have previews.
      ${occ} --no-interaction preview:generate-all

      echo ">>> reindex complete"
    '';

    serviceConfig = {
      Type = "oneshot";
      User = "nextcloud";
      Group = "nextcloud";
      TimeoutStartSec = "infinity";
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
    };
  };
}
