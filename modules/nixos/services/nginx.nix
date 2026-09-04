{ ... }:

{
  _module.args.mkProxyHost =
    {
      port,
      scheme ? "http",
      websockets ? true,
      locationExtraConfig ? "",
    }:
    {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "${scheme}://127.0.0.1:${toString port}";
        proxyWebsockets = websockets;
        extraConfig = locationExtraConfig;
      };
    };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    commonHttpConfig = ''
      log_format timed '$remote_addr $host "$request" $status '
                       'sent=$body_bytes_sent rt=$request_time '
                       'urt="$upstream_response_time" ua="$http_user_agent"';
    '';
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@shimme.rs";
  };

  users.users.nginx.extraGroups = [ "acme" ];

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
