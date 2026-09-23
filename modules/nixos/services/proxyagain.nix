{ mkProxyHost, ... }:

{
  services.proxyagain = {
    enable = true;
    listenHost = "127.0.0.1";
    listenPort = 3082;
    originalHost = "https://api.helloagain.at";
  };

  services.nginx.virtualHosts."api.p.5-htp.store" = mkProxyHost {
    port = 3082;
    websockets = false;
  };
}
