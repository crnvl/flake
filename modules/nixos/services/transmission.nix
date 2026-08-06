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

      ratio-limit = 1.0;
      ratio-limit-enabled = true;
      idle-seeding-limit = 1440;
      idle-seeding-limit-enabled = true;

      seed-queue-enabled = false;

      peer-limit-global = 1000;
      peer-limit-per-torrent = 100;

      port-forwarding-enabled = false;

      download-queue-size = 10;
      download-queue-enabled = true;
      download-dir = "/var/lib/transmission/downloads";
      incomplete-dir = "/var/lib/transmission/incomplete";
      incomplete-dir-enabled = true;
      preallocation = 0; # "none" - avoid reserving full file size for undownloaded data
      umask = 2;
    };
  };

  my.vpn = {
    confinedServices = [ "transmission" ];
    ports = [ 9091 ];
  };

  systemd = {
    tmpfiles.rules = [
      "d /var/lib/transmission/downloads 0775 transmission media -"
      "d /var/lib/transmission/downloads/radarr 0775 transmission media -"
      "d /var/lib/transmission/downloads/sonarr 0775 transmission media -"
      "d /var/lib/transmission/incomplete 0755 transmission transmission -"
    ];
  };

  users = {
    groups.media = { };
    users.transmission.extraGroups = [ "media" ];
  };
}
