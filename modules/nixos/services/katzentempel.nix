{ mkProxyHost, ... }:

{
  imports = [ ./katzentempel/module.nix ];

  services.katzentempelProxy = {
    enable = true;
    listenHost = "127.0.0.1";
    # 3083 belongs to location-ingest on shimmers.
    listenPort = 3084;
    originalHost = "https://api.helloagain.at";
  };

  # No query strings, authorization headers, or bodies in the access log.
  services.nginx.commonHttpConfig = ''
    log_format katzentempel '$time_iso8601 $request_method $uri $status';
  '';
  services.nginx.virtualHosts."katzentempel.shimme.rs" = (mkProxyHost {
    port = 3084;
    websockets = false;
    locationExtraConfig = ''
      client_max_body_size 32m;
    '';
  }) // {
    extraConfig = ''
      access_log /var/log/nginx/katzentempel.access.log katzentempel;
    '';
  };
}
