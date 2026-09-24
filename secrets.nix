let
  keys = import ./keys.nix;
  users = builtins.attrValues keys.users;

  perHost = {
    shimmers = [
      "kanidm-idm-admin-password"
      "kanidm-admin-password"
      "kanidm-oauth2-jellyfin-secret"
      "kanidm-oauth2-catshift-secret"
      "kanidm-oauth2-vaultwarden-secret"
      "kanidm-oauth2-nextcloud-secret"
      "kanidm-oauth2-grafana-secret"
      "grafana-secret-key"
      "alertmanager-env"
      "mullvad-wg.conf"
      "caelo-env"
      "chroma-smb"
      "radarr-api-key"
      "sonarr-api-key"
      "jellyfin-api-key"
      "media-janitor-webhook"
      "decluttarr-env"
      "vaultwarden-env"
      "oura-env"
      "location-env"
      "proxyagain-deploy-key"
      "vaultwarden-borg-passphrase"
      "nextcloud-admin-password"
      "maddy-rxby-password"
    ];

  };
in
builtins.listToAttrs (
  builtins.concatMap (
    host:
    map (name: {
      name = "hosts/${host}/secrets/${name}.age";
      value.publicKeys = users ++ [ keys.hosts.${host} ];
    }) perHost.${host}
  ) (builtins.attrNames perHost)
)
