{ ... }:

{
  services.sabnzbd.enable = true;

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
