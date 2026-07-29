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
      "kanidm-oauth2-beat-secret"
      "mullvad-wg.conf"
      "caelo-env"
      "chroma-smb"
      "radarr-api-key"
      "vaultwarden-env"
      "beat-env"
      "vaultwarden-borg-passphrase"
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
