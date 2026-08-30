{
  config,
  lib,
  pkgs,
  ...
}:

let
  domain = "cloud.shimme.rs";
  occ = lib.getExe config.services.nextcloud.occ;
in
{
  age.secrets = {
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
    enable = true;
    package = pkgs.nextcloud34;
    hostName = domain;
    https = true;

    maxUploadSize = "16G";
    configureRedis = true;
    database.createLocally = true;

    appstoreEnable = true;

    config = {
      dbtype = "pgsql";
      adminuser = "admin";
      adminpassFile = config.age.secrets.nextcloud-admin-password.path;
    };

    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps)
        user_oidc
        calendar
        contacts
        notes
        tasks
        ;
    };

    settings = {
      default_phone_region = "DE";
      overwriteprotocol = "https";
      log_type = "file";
      loglevel = 2;
      maintenance_window_start = 1;
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
}
