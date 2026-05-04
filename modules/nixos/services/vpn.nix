{ config, lib, ... }:

{
  options.my.vpn.portMappings = lib.mkOption {
    type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
    default = [ ];
    description = "List of port mappings for the VPN service.";
  };

  config = {
    age.secrets.mullvad-wg-config.file = ../../../hosts/shimmers/secrets/mullvad-wg.conf.age;

    vpnNamespaces.wg = {
      enable = true;
      wireguardConfigFile = config.age.secrets.mullvad-wg-config.path;
      accessibleFrom = [ "127.0.0.0/8" ];
      portMappings = config.my.vpn.portMappings;
    };
  };
}
