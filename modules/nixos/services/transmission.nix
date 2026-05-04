{ config, ... }:

let
  wgNamespace = config.vpnNamespaces."wg";
in
{
  services.transmission = {
    enable = true;
    settings = {
      rpc-bind-address = "0.0.0.0";
      rpc-port = 9091;
      rpc-whitelist-enabled = true;
      rpc-host-whitelist-enabled = false;
      rpc-whitelist = "127.0.0.1,${wgNamespace.bridgeAddress}";
      ratio-limit = 0;
      ratio-limit-enabled = true;
      download-queue-size = 10;
      download-queue-enabled = true;
      download-dir = "/var/lib/transmission/downloads";
      incomplete-dir = "/var/lib/transmission/incomplete";
      incomplete-dir-enabled = true;
      umask = 2;
    };
  };

  my.vpn.portMappings = [
    {
      from = 9091;
      to = 9091;
    }
  ];

  systemd = {
    services.transmission.vpnConfinement = {
      enable = true;
      vpnNamespace = "wg";
    };

    tmpfiles.rules = [
      "d /var/lib/transmission/downloads 0775 transmission media -"
      "d /var/lib/transmission/downloads/radarr 0775 transmission media -"
      "d /var/lib/transmission/downloads/sonarr 0775 transmission media -"
      "d /var/lib/transmission/incomplete 0755 transmission transmission -"
      "d /data/media/movies 0775 transmission media -"
      "d /data/media/tv 0775 transmission media -"
    ];
  };

  users = {
    groups.media = { };
    users.transmission.extraGroups = [ "media" ];
  };
}
