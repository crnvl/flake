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
  publicDashboardToken = null;

  httpsProbes = [
    "https://id.shimme.rs"
    "https://jellyfin.shimme.rs"
    "https://vault.shimme.rs"
    "https://cloud.shimme.rs"
    "https://seerr.shimme.rs"
    "https://shift.shimme.rs"
    "https://vitals.shimme.rs"
    "https://mail.shimme.rs"
    "https://${domain}"
  ];

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
in
{
  # Shared with kanidm (owner) and grafana (group) for the OIDC client.
  age.secrets.kanidm-oauth2-grafana-secret = {
    file = ../../../hosts/shimmers/secrets/kanidm-oauth2-grafana-secret.age;
    owner = "kanidm";
    group = "grafana";
    mode = "0440";
  };

  age.secrets.grafana-secret-key = {
    file = ../../../hosts/shimmers/secrets/grafana-secret-key.age;
    owner = "grafana";
    group = "grafana";
  };

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    retentionTime = "90d";
    globalConfig.scrape_interval = "30s";

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
        static_configs = [ { targets = httpsProbes; } ];
        relabel_configs = blackboxRelabel;
      }
      {
        job_name = "blackbox-imaps";
        metrics_path = "/probe";
        params.module = [ "tcp_tls" ];
        static_configs = [ { targets = [ "mail.shimme.rs:993" ]; } ];
        relabel_configs = blackboxRelabel;
      }
      {
        job_name = "blackbox-smtp";
        metrics_path = "/probe";
        params.module = [ "smtp_banner" ];
        static_configs = [ { targets = [ "mail.shimme.rs:25" ]; } ];
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
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://127.0.0.1:9090";
          isDefault = true;
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

  # Public status page: only the shared-dashboard routes and the static assets
  # they need are proxied; everything else (login, API, admin) stays private
  # behind grafana.shimme.rs.
  services.nginx.virtualHosts.${statusDomain} = {
    enableACME = true;
    forceSSL = true;

    locations =
      {
        "^~ /public-dashboards/" = grafanaProxy;
        "^~ /api/public/" = grafanaProxy;
        "^~ /public/" = grafanaProxy;
        "= /favicon.ico" = grafanaProxy;
      }
      // lib.optionalAttrs (publicDashboardToken != null) {
        "= /".return = "302 /public-dashboards/${publicDashboardToken}";
      };
  };
}
