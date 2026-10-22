{
  config,
  lib,
  mkProxyHost,
  ...
}:

let
  domain = "music.shimme.rs";

  # Subsonic API (apps, Lidarr's library-update connection), public share
  # links and navidrome's own password login (Feishin's Navidrome mode) can't
  # do a browser OIDC flow; they keep navidrome's own auth.
  # Clearing Remote-User matters: nginx connects from 127.0.0.1, which
  # navidrome trusts, so a client-supplied header would otherwise be honoured.
  bypassAuth = {
    proxyPass = "http://127.0.0.1:4533";
    extraConfig = ''
      auth_request off;
      proxy_set_header Remote-User "";
    '';
  };
in
{
  services.navidrome = {
    enable = true;
    openFirewall = false;

    settings = {
      Address = "127.0.0.1";
      Port = 4533;
      # Lidarr's root folder, next to media/movies and media/tv on the
      # storage box (also Jellyfin's music library).
      MusicFolder = "/mnt/chroma/media/music";

      # No inotify over CIFS, so the folder watcher is useless; rescan on a
      # schedule instead. Lidarr can also trigger a scan right after imports
      # via a Subsonic connection (Settings > Connect) pointed at navidrome.
      Scanner = {
        WatcherWait = "0";
        Schedule = "@every 1h";
      };

      # Web UI login comes from oauth2-proxy/kanidm via nginx. Unknown
      # usernames are created on first login (random password, which the
      # user can replace without knowing it, for Subsonic apps).
      ExtAuth = {
        TrustedSources = "127.0.0.1/32";
        UserHeader = "Remote-User";
        LogoutURL = "https://${domain}/oauth2/sign_out";
      };

      # Scrobbling and artist info. The API key and secret come from
      # navidrome-lastfm-env below; each user links their own Last.fm
      # account in the web UI (Personal > Scrobble to Last.fm).
      LastFM.Enabled = true;
    };
  };

  # Contains ND_LASTFM_APIKEY=... and ND_LASTFM_SECRET=... (the same Last.fm
  # API account aurral uses). Navidrome reads ND_* variables as config, which
  # keeps both out of the nix store.
  age.secrets.navidrome-lastfm-env.file = ../../../hosts/shimmers/secrets/navidrome-lastfm-env.age;
  systemd.services.navidrome.serviceConfig.EnvironmentFile =
    config.age.secrets.navidrome-lastfm-env.path;

  # The library is 0664/0775 jellyfin:media on the CIFS mount, so the world
  # read bits suffice; navidrome runs with PrivateUsers=true, under which
  # supplementary groups like media would be unmapped anyway.
  systemd.services.navidrome.unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];

  age.secrets.kanidm-oauth2-navidrome-secret = {
    file = ../../../hosts/shimmers/secrets/kanidm-oauth2-navidrome-secret.age;
    owner = "kanidm";
    group = "kanidm";
  };
  age.secrets.oauth2-proxy-cookie-secret.file =
    ../../../hosts/shimmers/secrets/oauth2-proxy-cookie-secret.age;

  services.oauth2-proxy = {
    enable = true;
    provider = "oidc";
    oidcIssuerUrl = "https://id.shimme.rs/oauth2/openid/navidrome";
    clientID = "navidrome";
    # Read via LoadCredential (as root), so kanidm's copy is shared.
    clientSecretFile = config.age.secrets.kanidm-oauth2-navidrome-secret.path;
    cookie.secretFile = config.age.secrets.oauth2-proxy-cookie-secret.path;
    redirectURL = "https://${domain}/oauth2/callback";
    # Who may log in is decided by kanidm's navidrome_users scope map.
    email.domains = [ "*" ];
    reverseProxy = true;
    trustedProxyIP = [ "127.0.0.1/32" ];
    setXauthrequest = true;
    extraConfig = {
      code-challenge-method = "S256";
      skip-provider-button = true;
      provider-display-name = "Kanidm";
    };

    nginx = {
      inherit domain;
      virtualHosts.${domain} = { };
    };
  };

  systemd.services.oauth2-proxy = {
    after = [ "kanidm.service" ];
    wants = [ "kanidm.service" ];
  };

  services.nginx.virtualHosts.${domain} = lib.mkMerge [
    (mkProxyHost { port = 4533; })
    {
      # kanidm's sub is a UUID; navidrome usernames should be the short name.
      locations."/".extraConfig = ''
        auth_request_set $navidrome_user $upstream_http_x_auth_request_preferred_username;
        proxy_set_header Remote-User $navidrome_user;
      '';
      locations."/rest/" = bypassAuth;
      locations."/share/" = bypassAuth;
      # Only the login itself; /auth/createAdmin stays behind oauth2-proxy.
      locations."= /auth/login" = bypassAuth;

      # The native API serves two kinds of clients. The web UI logs in via
      # the Remote-User header and gets no JWT from that, so its /api calls
      # need oauth2-proxy and the header like everything else. Clients that
      # logged in at /auth/login (Feishin) send navidrome's JWT instead and
      # have no oauth2-proxy cookie. So: with a JWT, skip oauth2-proxy and
      # leave Remote-User empty (navidrome then checks the JWT); without
      # one, the usual oauth2-proxy check and header.
      locations."/api/" = {
        proxyPass = "http://127.0.0.1:4533";
        extraConfig = ''
          auth_request /_navidrome_api_auth;
          auth_request_set $navidrome_user $upstream_http_x_auth_request_preferred_username;
          proxy_set_header Remote-User $navidrome_user;
        '';
      };
      locations."= /_navidrome_api_auth" = {
        proxyPass = "${config.services.oauth2-proxy.httpAddress}/oauth2/auth?";
        extraConfig = ''
          internal;
          auth_request off;
          if ($http_x_nd_authorization) {
            return 204;
          }
          # same as the oauth2-proxy module's /oauth2/auth location
          proxy_set_header X-Scheme $scheme;
          proxy_set_header Content-Length "";
          proxy_pass_request_body off;
        '';
      };
    }
  ];
}
