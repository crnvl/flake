{ ... }:

{
  age.secrets.stalwart-admin-password = {
    file = ../../../hosts/shimmers/secrets/stalwart-admin-password.age;
    owner = "stalwart";
    group = "stalwart";
  };

  systemd.services.stalwart.serviceConfig.BindReadOnlyPaths = [
    "/run/agenix/stalwart-admin-password"
  ];

  services.stalwart = {
    enable = true;
    stateVersion = "26.05";
    openFirewall = true;

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
          http = {
            bind = [ "0.0.0.0:8080" ];
            protocol = "http";
          };
        };

        tls.certificate = "default";
      };

      certificate.default = {
        cert = "%{file:/var/lib/acme/mail.shimme.rs/fullchain.pem}%";
        private-key = "%{file:/var/lib/acme/mail.shimme.rs/key.pem}%";
      };

      tracer = {
        journal.enable = false;
        stdout = {
          type = "stdout";
          level = "info";
          ansi = false;
          enable = true;
        };
      };

      storage.directory = "internal";

      authentication = {
        directory = "internal";
        fallback-admin = {
          user = "admin";
          secret = "%{file:/run/agenix/stalwart-admin-password}%";
        };
      };
    };
  };

  security.acme.certs."mail.shimme.rs" = {
    group = "acme";
    reloadServices = [ "stalwart" ];
  };

  users.users.stalwart.extraGroups = [ "acme" ];

  services.nginx.virtualHosts."mail.shimme.rs" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
      proxyWebsockets = true;
    };
  };
}
