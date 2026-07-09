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

  my.vpn = {
    confinedServices = [ "prowlarr" ];
    ports = [ 9696 ];
  };
}
