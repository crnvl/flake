{ ... }:

{
  services.jellyseerr = {
    enable = true;
    openFirewall = false;
  };

  services.nginx.virtualHosts."seerr.shimme.rs" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5055";
      proxyWebsockets = true;
    };
  };
}
