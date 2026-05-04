{ ... }:

{
  services.radarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.radarr.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };

  users.users.radarr.extraGroups = [
    "media"
    "transmission"
  ];

  my.vpn.portMappings = [
    {
      from = 7878;
      to = 7878;
    }
  ];
}
