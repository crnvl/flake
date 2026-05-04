{ ... }:

{
  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.prowlarr.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };

  my.vpn.portMappings = [
    {
      from = 9696;
      to = 9696;
    }
  ];
}
