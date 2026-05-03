{ ... }:

{
  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  services.nginx.virtualHosts."jellyfin.shimme.rs" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:8096";
      proxyWebsockets = true;
    };
  };
}
