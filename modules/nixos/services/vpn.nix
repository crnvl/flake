{ config, lib, ... }:

let
  cfg = config.my.vpn;
in
{
  options.my.vpn = {
    confinedServices = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "systemd service names to confine to the wg VPN namespace.";
    };

    ports = lib.mkOption {
      type = with lib.types; listOf port;
      default = [ ];
      description = "Ports mapped identically (from == to) into the VPN namespace.";
    };

    portMappings = lib.mkOption {
      type = with lib.types; listOf (attrsOf anything);
      default = [ ];
      description = "Explicit from/to port mappings (escape hatch).";
    };
  };

  config = {
    age.secrets.mullvad-wg-config.file = ../../../hosts/shimmers/secrets/mullvad-wg.conf.age;

    systemd.services = lib.genAttrs cfg.confinedServices (_: {
      vpnConfinement = {
        enable = true;
        vpnNamespace = "wg";
      };
    });

    vpnNamespaces.wg = {
      enable = true;
      wireguardConfigFile = config.age.secrets.mullvad-wg-config.path;
      accessibleFrom = [ "127.0.0.0/8" ];
      portMappings =
        cfg.portMappings
        ++ map (p: {
          from = p;
          to = p;
        }) cfg.ports;
    };
  };
}
