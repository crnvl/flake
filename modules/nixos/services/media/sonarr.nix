{ ... }:

{
  services.sonarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.sonarr.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };

  users.users.sonarr.extraGroups = [
    "media"
    "transmission"
    "sabnzbd"
  ];

  my.vpn.portMappings = [
    {
      from = 8989;
      to = 8989;
    }
  ];
}
