let
  keys = import ./keys.nix;
  users = builtins.attrValues keys.users;
  shimmers = keys.hosts.shimmers;
in
{
  "hosts/shimmers/secrets/kanidm-idm-admin-password.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/kanidm-admin-password.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/kanidm-oauth2-jellyfin-secret.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/kanidm-oauth2-catshift-secret.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/mullvad-wg.conf.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/caelo-env.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/chroma-smb.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/radarr-api-key.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/vaultwarden-env.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/vaultwarden-borg-passphrase.age".publicKeys = users ++ [ shimmers ];
}
