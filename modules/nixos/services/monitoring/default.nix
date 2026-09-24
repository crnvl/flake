{
  config,
  pkgs,
  lib,
  mkProxyHost,
  ...
}:

let
  domain = "grafana.shimme.rs";
  statusDomain = "status.shimme.rs";

  # After creating a shared (public) dashboard in Grafana, paste its token here
  # (the part after /public-dashboards/ in the share URL) so that
  # https://status.shimme.rs/ redirects straight to it.
  publicDashboardToken = "3d7dabda6fbb466290e14b1a59568743";

  # Friendly names end up as the "service" label, so panels can use
  # {{service}} in their legend instead of the raw instance URL.
  httpsProbes = {
    "Identity" = "https://id.shimme.rs";
    "Jellyfin" = "https://jellyfin.shimme.rs";
    "Vault" = "https://vault.shimme.rs";
    "Cloud" = "https://cloud.shimme.rs";
    "Seerr" = "https://seerr.shimme.rs";
    "Shift" = "https://shift.shimme.rs";
    "Webmail" = "https://mail.shimme.rs";
    "Grafana" = "https://${domain}";
  };

  mkProbeTargets =
    probes:
    lib.mapAttrsToList (name: url: {
      targets = [ url ];
      labels.service = name;
    }) probes;

  blackboxConfig = pkgs.writeText "blackbox.yml" (
    builtins.toJSON {
      modules = {
        http_2xx = {
          prober = "http";
          timeout = "10s";
        };
        tcp_tls = {
          prober = "tcp";
          timeout = "10s";
          tcp.tls = true;
        };
        smtp_banner = {
          prober = "tcp";
          timeout = "10s";
          tcp.query_response = [ { expect = "^220 "; } ];
        };
      };
    }
  );

  blackboxRelabel = [
    {
      source_labels = [ "__address__" ];
      target_label = "__param_target";
    }
    {
      source_labels = [ "__param_target" ];
      target_label = "instance";
    }
    {
      target_label = "__address__";
      replacement = "127.0.0.1:9115";
    }
  ];

  grafanaProxy = {
    proxyPass = "http://127.0.0.1:3000";
    proxyWebsockets = true;
  };

  # A public dashboard host: only the shared-dashboard routes and the static
  # assets they need are proxied; everything else (login, API, admin) stays
  # private behind grafana.shimme.rs. / redirects to one specific dashboard
  # once its share token is known.
  mkPublicDashboardHost = token: {
    enableACME = true;
    forceSSL = true;

    locations =
      {
        "^~ /public-dashboards/" = grafanaProxy;
        "^~ /api/public/" = grafanaProxy;
        "^~ /public/" = grafanaProxy;
        "= /favicon.ico" = grafanaProxy;
      }
      // lib.optionalAttrs (token != null) {
        "= /".return = "302 /public-dashboards/${token}";
      };
  };
in
{
  # Oura ring metrics, surfaced on the "vitals" dashboard.
  imports = [
    ./oura.nix
    ./location.nix
  ];

  # Shared with kanidm (owner) and grafana (group) for the OIDC client.
  age.secrets.kanidm-oauth2-grafana-secret = {
    file = ../../../../hosts/shimmers/secrets/kanidm-oauth2-grafana-secret.age;
    owner = "kanidm";
    group = "grafana";
    mode = "0440";
  };

  age.secrets.grafana-secret-key = {
    file = ../../../../hosts/shimmers/secrets/grafana-secret-key.age;
    owner = "grafana";
    group = "grafana";
  };

  # Contains DISCORD_WEBHOOK=<id>/<token>; substituted into the alertmanager
  # config at runtime so the webhook never lands in the nix store. Only the
  # secret part is a variable: the build-time config check (amtool) requires
  # webhook_url to parse as a URL, which a bare $VAR placeholder doesn't.
  age.secrets.alertmanager-env.file = ../../../../hosts/shimmers/secrets/alertmanager-env.age;

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    retentionTime = "90d";
    globalConfig.scrape_interval = "30s";

    alertmanagers = [
      { static_configs = [ { targets = [ "127.0.0.1:9093" ]; } ]; }
    ];

    rules = [
      (builtins.toJSON {
        groups = [
          {
            name = "status";
            rules = [
              {
                alert = "ServiceDown";
                expr = "probe_success == 0";
                for = "3m";
                labels.severity = "critical";
                annotations = {
                  summary = "{{ $labels.service }} is currently unavailable.";
                  resolved = "{{ $labels.service }} is back online.";
                };
              }
              {
                alert = "SystemdUnitFailed";
                expr = ''systemd_unit_state{state="failed"} == 1'';
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "A background service ({{ $labels.name }}) has failed.";
                  resolved = "Background service {{ $labels.name }} has recovered.";
                };
              }
              {
                alert = "DiskSpaceLow";
                expr = ''node_filesystem_avail_bytes{mountpoint=~"/|/mnt/chroma"} / node_filesystem_size_bytes < 0.10'';
                for = "15m";
                labels.severity = "warning";
                annotations = {
                  summary = "The server is running low on storage.";
                  resolved = "Server storage is back at a safe level.";
                };
              }
              {
                alert = "TlsCertExpiringSoon";
                expr = "(probe_ssl_earliest_cert_expiry - time()) / 86400 < 10";
                for = "1h";
                labels.severity = "warning";
                annotations = {
                  summary = "The certificate for {{ $labels.service }} expires in less than 10 days.";
                  resolved = "The certificate for {{ $labels.service }} was renewed.";
                };
              }
            ];
          }
        ];
      })
    ];

    alertmanager = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9093;
      environmentFile = config.age.secrets.alertmanager-env.path;

      configuration = {
        route = {
          receiver = "discord";
          group_by = [ "alertname" ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "24h";
        };

        receivers = [
          {
            name = "discord";
            discord_configs = [
              {
                webhook_url = "https://discord.com/api/webhooks/$DISCORD_WEBHOOK";
                username = "status.shimme.rs";
                send_resolved = true;

                # Keep the channel human-readable: one line per alert, no
                # label/annotation dumps or Prometheus source links.
                title = ''{{ if .Alerts.Firing }}🔴 Service disruption{{ else }}🟢 Resolved{{ end }}'';
                message = ''
                  {{ range .Alerts.Firing }}{{ .Annotations.summary }}
                  {{ end }}{{ range .Alerts.Resolved }}{{ .Annotations.resolved }}
                  {{ end }}'';
              }
            ];
          }
        ];
      };
    };

    exporters = {
      node = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9100;
      };

      systemd = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9558;
      };

      nginx = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9113;
      };

      blackbox = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9115;
        configFile = blackboxConfig;
      };
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [ { targets = [ "127.0.0.1:9100" ]; } ];
      }
      {
        job_name = "systemd";
        static_configs = [ { targets = [ "127.0.0.1:9558" ]; } ];
      }
      {
        job_name = "nginx";
        static_configs = [ { targets = [ "127.0.0.1:9113" ]; } ];
      }
      {
        job_name = "prometheus";
        static_configs = [ { targets = [ "127.0.0.1:9090" ]; } ];
      }
      {
        job_name = "grafana";
        static_configs = [ { targets = [ "127.0.0.1:3000" ]; } ];
      }
      {
        job_name = "blackbox-https";
        metrics_path = "/probe";
        params.module = [ "http_2xx" ];
        static_configs = mkProbeTargets httpsProbes;
        relabel_configs = blackboxRelabel;
      }
      {
        job_name = "blackbox-imaps";
        metrics_path = "/probe";
        params.module = [ "tcp_tls" ];
        static_configs = mkProbeTargets { "Mail (IMAP)" = "mail.shimme.rs:993"; };
        relabel_configs = blackboxRelabel;
      }
      {
        job_name = "blackbox-smtp";
        metrics_path = "/probe";
        params.module = [ "smtp_banner" ];
        static_configs = mkProbeTargets { "Mail (SMTP)" = "mail.shimme.rs:25"; };
        relabel_configs = blackboxRelabel;
      }
    ];
  };

  # stub_status endpoint on localhost for the nginx exporter.
  services.nginx.statusPage = true;

  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain = domain;
        root_url = "https://${domain}";
        enable_gzip = true;
      };

      analytics.reporting_enabled = false;
      users.allow_sign_up = false;
      security = {
        cookie_secure = true;
        secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
      };

      # Shared dashboards, exposed read-only via status.shimme.rs below.
      public_dashboards.enabled = true;

      "auth.generic_oauth" = {
        enabled = true;
        name = "Kanidm";
        client_id = "grafana";
        client_secret = "$__file{${config.age.secrets.kanidm-oauth2-grafana-secret.path}}";
        scopes = "openid profile email groups";
        auth_url = "https://id.shimme.rs/ui/oauth2";
        token_url = "https://id.shimme.rs/oauth2/token";
        api_url = "https://id.shimme.rs/oauth2/openid/grafana/userinfo";
        use_pkce = true;
        use_refresh_token = true;
        allow_sign_up = true;
        login_attribute_path = "preferred_username";
        role_attribute_path = "contains(grafana_role[*], 'admin') && 'Admin' || 'Viewer'";
      };
    };

    provision = {
      enable = true;

      # The datasource originally got an auto-generated uid before we pinned
      # uid = "prometheus"; grafana's provisioner updates by uid, so it can't
      # reconcile the rename on its own ("data source not found" at startup).
      # Deleting by name first makes the insert idempotent.
      datasources.settings = {
        deleteDatasources = [
          {
            name = "Prometheus";
            orgId = 1;
          }
        ];

        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            uid = "prometheus";
            url = "http://127.0.0.1:9090";
            isDefault = true;
          }
          # victoriametrics is PromQL-compatible; the oura dashboard reads
          # the ring's history from here (see oura.nix).
          {
            name = "VictoriaMetrics";
            type = "prometheus";
            uid = "victoriametrics";
            url = "http://127.0.0.1:8428";
          }
        ];
      };

      dashboards.settings.providers = [
        {
          name = "declarative";
          type = "file";
          disableDeletion = true;
          options.path = ./dashboards;
        }
      ];
    };
  };

  services.kanidm.provision = {
    groups = {
      grafana_users = { };
      grafana_admins = { };
    };

    persons.aleph.groups = [
      "grafana_users"
      "grafana_admins"
    ];

    systems.oauth2.grafana = {
      displayName = "grafana";
      originUrl = "https://${domain}/login/generic_oauth";
      originLanding = "https://${domain}";
      basicSecretFile = config.age.secrets.kanidm-oauth2-grafana-secret.path;
      preferShortUsername = true;

      scopeMaps.grafana_users = [
        "openid"
        "profile"
        "email"
        "groups"
      ];

      claimMaps.grafana_role = {
        joinType = "array";
        valuesByGroup.grafana_admins = [ "admin" ];
      };
    };
  };

  services.nginx.virtualHosts.${domain} = mkProxyHost { port = 3000; };

  # Public status page.
  services.nginx.virtualHosts.${statusDomain} = mkPublicDashboardHost publicDashboardToken;
}
