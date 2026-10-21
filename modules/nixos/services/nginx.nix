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

    # *.shimme.rs is a wildcard record, so typos and scanners land here with
    # names no vhost claims. Without an explicit default, nginx hands them to
    # whichever vhost sorts first (then api.p.5-htp.store), certificate and
    # all. Refuse them instead: no TLS handshake, and 444 (close) on plain HTTP.
    virtualHosts."_" = {
      default = true;
      rejectSSL = true;
      locations."/".return = "444";
    };
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
