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

  # The slots dashboard's public copy (dashboards/slots-public.json), shared
  # at https://insights.slots.shimme.rs/ under this token. Unlike the status
  # page it is shared by grafana-setup below, so nothing is pasted by hand:
  # any 32 hex digits will do.
  slotsInsightsDomain = "insights.slots.shimme.rs";
  slotsInsightsToken = "b259a437585ba214394bfdc838e5dbb1";

  # Friendly names end up as the "service" label, so panels can use
  # {{service}} in their legend instead of the raw instance URL.
  httpsProbes = {
    "Identity" = "https://id.shimme.rs";
    "Jellyfin" = "https://jellyfin.shimme.rs";
    "Vault" = "https://vault.shimme.rs";
    "Seerr" = "https://seerr.shimme.rs";
    # / redirects to kanidm; the Subsonic API bypasses it and answers 200
    # (with an auth error body) only if navidrome itself is up.
    "Music" = "https://music.shimme.rs/rest/ping.view";
    "Aurral" = "https://aurral.shimme.rs";
    "Shift" = "https://shift.shimme.rs";
    "Share" = "https://share.shimme.rs";
    # The portal/API process only; never touches (or wakes) the paid GPU.
    "Infer" = "https://infer.shimme.rs/healthz";
    # Answers without signing in; the dashboard's site stat reads this too.
    "Slots" = "https://slots.shimme.rs/healthz";
    "Webmail" = "https://mail.shimme.rs";
    "Grafana" = "https://${domain}";
  }
  // lib.optionalAttrs config.services.nextcloud.enable {
    "Cloud" = "https://cloud.shimme.rs";
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

  # Grafana's own admin account. It was created with the default password,
  # which the admin_password setting cannot change afterwards; grafana-setup
  # changes it once. Read it with agenix if you ever need it.
  age.secrets.grafana-admin-password = {
    file = ../../../../hosts/shimmers/secrets/grafana-admin-password.age;
    owner = "grafana";
    group = "grafana";
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

    # Each module contributes its own file via ruleFiles: entries in `rules`
    # get concatenated into a single file, and two concatenated JSON
    # documents are not valid YAML - only the first group would load.
    ruleFiles = [
      (pkgs.writeText "status-rules.json" (builtins.toJSON {
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
                # Periodic oneshot timers briefly leave the "failed" state
                # (entering "activating") on each retry; hold the alert across
                # those runs so a sustained outage doesn't resolve and re-fire
                # on every timer tick.
                keep_firing_for = "15m";
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
                alert = "DiskSpaceAlmostFull";
                expr = ''node_filesystem_avail_bytes{mountpoint=~"/|/mnt/chroma"} / node_filesystem_size_bytes < 0.03'';
                for = "15m";
                labels.severity = "critical";
                annotations = {
                  summary = "The server is almost out of storage.";
                  resolved = "Server storage is no longer almost full.";
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
      }))
    ];

    alertmanager = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9093;
      environmentFile = config.age.secrets.alertmanager-env.path;

      # How long alertmanager remembers what it already sent. Once that is
      # gone, a still firing alert counts as new and gets sent again, so this
      # caps every repeat_interval below; the default is 120h.
      extraFlags = [ "--data.retention=8760h" ];

      configuration = {
        route = {
          receiver = "discord";
          group_by = [ "alertname" ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "24h";

          routes = [
            {
              # Storage fills up over weeks, so a daily reminder is just
              # noise: one message when it gets low, one more when it is
              # almost full (a separate alert, so a separate message), and
              # the resolved ones. A year is as close to never as it gets.
              matchers = [ ''alertname=~"DiskSpaceLow|DiskSpaceAlmostFull"'' ];
              repeat_interval = "8760h";
            }
          ];
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
        # Only used when the admin account is first created; see grafana-setup.
        admin_password = "$__file{${config.age.secrets.grafana-admin-password.path}}";
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
      imageFile = ../kanidm-logos/grafana.svg;
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

  # Public slots dashboard.
  services.nginx.virtualHosts.${slotsInsightsDomain} = mkPublicDashboardHost slotsInsightsToken;

  # What grafana can only be told through its API: the admin password (see
  # age.secrets.grafana-admin-password) and which dashboards are shared.
  # Idempotent, so it simply runs after every start of grafana.
  systemd.services.grafana-setup = {
    description = "grafana: admin password and shared dashboards";
    after = [ "grafana.service" ];
    requires = [ "grafana.service" ];
    wantedBy = [
      "grafana.service"
      "multi-user.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      LoadCredential = [ "admin-password:${config.age.secrets.grafana-admin-password.path}" ];
      PrivateTmp = true;
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "grafana-setup";
          runtimeInputs = [
            pkgs.curl
            pkgs.jq
          ];
          text = ''
            api=http://127.0.0.1:3000
            password=$(cat "$CREDENTIALS_DIRECTORY/admin-password")

            # Credentials go to curl in files, not on its command line, where
            # every user on the host could read them.
            mine=$(mktemp)
            default=$(mktemp)
            printf 'user = "admin:%s"\n' "$password" > "$mine"
            printf 'user = "admin:admin"\n' > "$default"
            as() {
              local auth=$1
              shift
              curl --fail --silent --show-error --config "$auth" "$@"
            }

            for _ in $(seq 60); do
              curl --fail --silent --output /dev/null "$api/api/health" && break
              sleep 2
            done

            # Asking is expected to fail until the password has been set,
            # and the sharing below until it has been shared: quietly.
            if ! as "$mine" --output /dev/null "$api/api/user" 2> /dev/null; then
              echo "replacing grafana's default admin password"
              jq -n --arg new "$password" \
                '{oldPassword: "admin", newPassword: $new, confirmNew: $new}' |
                as "$default" --output /dev/null -X PUT -H 'Content-Type: application/json' \
                  --data @- "$api/api/user/password"
            fi

            share() {
              local uid=$1 token=$2
              for _ in $(seq 30); do
                as "$mine" --output /dev/null "$api/api/dashboards/uid/$uid" && break
                sleep 2
              done
              if as "$mine" "$api/api/dashboards/uid/$uid/public-dashboards" 2> /dev/null |
                jq -e '.accessToken' > /dev/null; then
                return 0
              fi
              echo "sharing dashboard $uid"
              jq -n --arg token "$token" \
                '{isEnabled: true, share: "public", accessToken: $token,
                  timeSelectionEnabled: true, annotationsEnabled: true}' |
                as "$mine" --output /dev/null -X POST -H 'Content-Type: application/json' \
                  --data @- "$api/api/dashboards/uid/$uid/public-dashboards"
            }

            share slots-public ${slotsInsightsToken}
          '';
        }
      );
    };
  };
}
