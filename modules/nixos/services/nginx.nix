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
