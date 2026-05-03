{ ... }:

{
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
