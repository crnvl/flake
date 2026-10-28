{ config, lib, ... }:

# disko (as of rev cedd626) sets `boot.initrd.systemd.enable = true` for every
# LUKS device with `enrollFido2 = true`. nixpkgs 26.11 removed that option
# because the systemd initrd is now the only initrd, so evaluating this host
# fails with:
#
#   The option definition `boot.initrd.systemd.enable' ... no longer has any
#   effect; please remove it. Scripted initrd has been removed.
#
# Drop the obsolete assignment from the config disko generates, and apply the
# rest of it ourselves, until disko removes the assignment upstream.
let
  obsoletePath = [
    "initrd"
    "systemd"
  ];

  # Walk disko's `_config.boot` module tree (mkMerge/mkIf/... nodes) and drop
  # the `initrd.systemd.enable` key wherever it appears, without flattening the
  # tree, so the module system still merges it exactly as disko intended.
  stripEnable =
    path: value:
    if lib.isAttrs value && value ? _type then
      if value._type == "merge" then
        value // { contents = map (stripEnable path) value.contents; }
      else if value._type == "if" then
        value // { content = stripEnable path value.content; }
      else if value._type == "override" then
        value // { content = stripEnable path value.content; }
      else
        value
    else if lib.isAttrs value then
      if path == obsoletePath then
        removeAttrs value [ "enable" ]
      else
        lib.mapAttrs (name: sub: stripEnable (path ++ [ name ]) sub) value
    else
      value;
in
{
  # Keep disko from applying its generated config (which contains the removed
  # option), then apply that same config ourselves.
  disko.enableConfig = false;

  fileSystems = lib.mkMerge [ (config.disko.devices._config.fileSystems or { }) ];
  swapDevices = lib.mkMerge [ (config.disko.devices._config.swapDevices or [ ]) ];

  boot = stripEnable [ ] (config.disko.devices._config.boot or { });
}
