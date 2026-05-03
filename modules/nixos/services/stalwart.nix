{ ... }:

{
  services.stalwart-mail = {
    enable = true;

    settings = {
      server = {
        hostname = "mail.shimme.rs";

        listener = {
          smtp = {
            bind = [ "0.0.0.0:25" ];
            protocol = "smtp";
          };
          imaps = {
            bind = [ "0.0.0.0:993" ];
            protocol = "imap";
            tls.implicit = true;
          };
        };

        tls = {
          certificate = "default";
        };
      };

      certificate.default = {
        cert = "%{file:/var/lib/acme/mail.shimme.rs/fullchain.pem}%";
        private-key = "%{file:/var/lib/acme/mail.shimme.rs/key.pem}%";
      };

      authentication.oauth = {
        enable = true;
        issuer-url = "https://id.shimme.rs/oauth2/openid/stalwart";
      };
    };
  };

  security.acme.certs."mail.shimme.rs" = {
    group = "acme";
    reloadServices = [ "stalwart-mail" ];
  };

  services.nginx.virtualHosts."mail.shimme.rs" = {
    enableACME = true;
    forceSSL = true;
  };

  networking.firewall.allowedTCPPorts = [
    25
    993
  ];
}
