{
  config,
  lib,
  ...
}:

let
  # maddy's own FQDN. Lives under shimme.rs (wildcard A record already points
  # here) so we never need a cert for a domain whose DNS lives at Contabo.
  # The MX record for 5-htp.store points at this name; that is what keeps
  # rxby@5-htp.store working after the migration.
  fqdn = "mail.shimme.rs";

  certDir = "/var/lib/acme/${fqdn}";

  # Canonical mailbox. Kept on the old domain so the existing mail can be
  # imapsync'd straight in; rxby@shimme.rs is an alias onto it.
  primaryAccount = "rxby@5-htp.store";
in
{
  age.secrets.maddy-rxby-password = {
    file = ../../../hosts/shimmers/secrets/maddy-rxby-password.age;
    owner = "maddy";
    group = "maddy";
  };

  services.maddy = {
    enable = true;

    hostname = fqdn;
    primaryDomain = "5-htp.store";
    localDomains = [
      "5-htp.store"
      "shimme.rs"
    ];

    tls = {
      loader = "file";
      certificates = [
        {
          certPath = "${certDir}/fullchain.pem";
          keyPath = "${certDir}/key.pem";
        }
      ];
    };

    # Receive-only. Hetzner blocks outbound :25 on cloud instances, so there is
    # deliberately no submission endpoint, no target.remote and no queue: we
    # cannot send, therefore we must never accept anything we'd have to bounce.
    # Unknown recipients are rejected inline at RCPT TO with a 5xx instead.
    config = ''
      auth.pass_table local_authdb {
        table sql_table {
          driver sqlite3
          dsn credentials.db
          table_name passwords
        }
      }

      storage.imapsql local_mailboxes {
        driver sqlite3
        dsn imapsql.db
      }

      table.chain local_rewrites {
        optional_step regexp "(.+)\+(.+)@(.+)" "$1@$3"
        optional_step static {
          entry postmaster postmaster@$(primary_domain)
        }
        optional_step file /etc/maddy/aliases
      }

      msgpipeline local_routing {
        destination postmaster $(local_domains) {
          modify {
            replace_rcpt &local_rewrites
          }
          deliver_to &local_mailboxes
        }
        default_destination {
          reject 550 5.1.1 "User doesn't exist"
        }
      }

      smtp tcp://0.0.0.0:25 {
        limits {
          all rate 20 1s
          all concurrency 10
        }
        # dmarc is deliberately off. Some inbound mail arrives via relays that
        # apply Sender Rewriting Scheme (envelope rewritten to SRS0=...@relay),
        # so SPF authenticates the relay rather than the From: domain and
        # DMARC's SPF leg cannot align; a pass then depends entirely on DKIM
        # surviving the hop. maddy's dmarc is a plain boolean with no
        # fail_action, so a p=reject sender whose signature didn't survive gets
        # a hard 550 -- silent mail loss. The old Postfix setup enforced no
        # DMARC at all, so this keeps behaviour equivalent rather than adding a
        # new way to lose mail.
        # The checks below still run and still annotate Authentication-Results;
        # spf's fail_action defaults to quarantine rather than reject.
        dmarc no
        check {
          require_mx_record
          dkim
          spf
        }
        source $(local_domains) {
          reject 501 5.1.8 "This server does not relay"
        }
        default_source {
          destination postmaster $(local_domains) {
            deliver_to &local_routing
          }
          default_destination {
            reject 550 5.1.1 "User doesn't exist"
          }
        }
      }

      imap tls://0.0.0.0:993 {
        auth &local_authdb
        storage &local_mailboxes
      }
    '';

    ensureAccounts = [ primaryAccount ];
    ensureCredentials.${primaryAccount}.passwordFile = config.age.secrets.maddy-rxby-password.path;
  };

  environment.etc."maddy/aliases".text = ''
    rxby@shimme.rs: ${primaryAccount}
    postmaster@5-htp.store: ${primaryAccount}
    postmaster@shimme.rs: ${primaryAccount}
    abuse@5-htp.store: ${primaryAccount}
    abuse@shimme.rs: ${primaryAccount}
  '';

  # Not services.maddy.openFirewall: that also opens 143 and 587, neither of
  # which we run.
  networking.firewall.allowedTCPPorts = [
    25
    993
  ];

  security.acme.certs.${fqdn} = {
    group = "acme";
    reloadServices = [
      "maddy"
      "nginx"
    ];
  };

  users.users.maddy.extraGroups = [ "acme" ];

  systemd.services = {
    maddy = {
      serviceConfig.BindReadOnlyPaths = [ "${certDir}/" ];
      restartTriggers = [ config.environment.etc."maddy/aliases".source ];
    };

    # Upstream's unit relies on WorkingDirectory to resolve the relative sqlite
    # DSNs above; the nixpkgs helper unit doesn't set one, so maddyctl would
    # otherwise create its databases in /.
    maddy-ensure-accounts.serviceConfig = {
      WorkingDirectory = "/var/lib/maddy";
      StateDirectory = "maddy";
    };
  };

  services.roundcube = {
    enable = true;
    hostName = fqdn;
    # Loopback via networking.hosts below, so the cert still validates.
    extraConfig = ''
      $config['imap_host'] = 'ssl://${fqdn}:993';
      $config['product_name'] = 'shimmers mail';
      $config['login_username_filter'] = 'email';
    '';
  };

  # Resolve our own FQDN locally so roundcube's IMAP connection doesn't have to
  # hairpin through the public IP. Same trick as id.shimme.rs.
  networking.hosts."127.0.0.1" = [ fqdn ];
}
