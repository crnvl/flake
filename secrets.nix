let
  keys = import ./keys.nix;
  users = builtins.attrValues keys.users;
  shimmers = keys.hosts.shimmers;

  secrets = [
    "kanidm-idm-admin-password"
    "kanidm-admin-password"
    "kanidm-oauth2-jellyfin-secret"
    "kanidm-oauth2-catshift-secret"
    "kanidm-oauth2-vaultwarden-secret"
    "mullvad-wg.conf"
    "caelo-env"
    "chroma-smb"
    "radarr-api-key"
    "vaultwarden-env"
    "vaultwarden-borg-passphrase"
  ];
in
builtins.listToAttrs (
  map (name: {
    name = "hosts/shimmers/secrets/${name}.age";
    value.publicKeys = users ++ [ shimmers ];
  }) secrets
)
