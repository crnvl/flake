{ mkProxyHost, ... }:

{
  services.seerr = {
    enable = true;
    openFirewall = false;
  };

  services.nginx.virtualHosts."seerr.shimme.rs" = mkProxyHost { port = 5055; };
}
