{ ... }:

{
  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  users.users.jellyfin.extraGroups = [ "media" ];

  services.nginx.virtualHosts."jellyfin.shimme.rs" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:8096";
      proxyWebsockets = true;

      extraConfig = ''
        proxy_set_header X-Forwarded-Proto https;
      '';
    };
  };
}
