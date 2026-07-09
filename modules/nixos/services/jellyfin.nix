{ mkProxyHost, ... }:

{
  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  users.users.jellyfin.extraGroups = [ "media" ];

  services.nginx.virtualHosts."jellyfin.shimme.rs" = mkProxyHost {
    port = 8096;
    locationExtraConfig = "proxy_set_header X-Forwarded-Proto https;";
  };
}
