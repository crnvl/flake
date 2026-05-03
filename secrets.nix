let
  keys = import ./keys.nix;
  users = builtins.attrValues keys.users;
  shimmers = keys.hosts.shimmers;
in
{
  "hosts/shimmers/secrets/kanidm-idm-admin-password.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/kanidm-admin-password.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/kanidm-oauth2-jellyfin-secret.age".publicKeys = users ++ [ shimmers ];
  "hosts/shimmers/secrets/stalwart-admin-password.age".publicKeys = users ++ [ shimmers ];
}
