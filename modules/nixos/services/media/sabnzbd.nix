{ lib, pkgs, ... }:

{
  services.sabnzbd = {
    enable = true;
  };

  systemd.services.sabnzbd.serviceConfig.ExecStart =
    lib.mkForce "${lib.getBin pkgs.sabnzbd}/bin/sabnzbd -d -f /var/lib/sabnzbd/sabnzbd.ini -s 0.0.0.0:8080 -b 0";

  systemd.services.sabnzbd.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };

  my.vpn.portMappings = [
    {
      from = 8080;
      to = 8080;
    }
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd/downloads 0775 sabnzbd media -"
    "d /var/lib/sabnzbd/downloads/radarr 0775 sabnzbd media -"
    "d /var/lib/sabnzbd/downloads/sonarr 0775 sabnzbd media -"
    "d /var/lib/sabnzbd/incomplete 0755 sabnzbd sabnzbd -"
  ];

  users.users.sabnzbd.extraGroups = [ "media" ];
}
