{
  config,
  lib,
  mkProxyHost,
  ...
}:

let
  domain = "aurral.shimme.rs";
  port = 3001;
in
{
  # Raw client secret for kanidm's basicSecretFile.
  age.secrets.kanidm-oauth2-aurral-secret = {
    file = ../../../../hosts/shimmers/secrets/kanidm-oauth2-aurral-secret.age;
    owner = "kanidm";
    group = "kanidm";
  };

  # Contains OIDC_CLIENT_SECRET=... (same value as kanidm-oauth2-aurral-secret);
  # aurral only reads it from the environment.
  age.secrets.aurral-env.file = ../../../../hosts/shimmers/secrets/aurral-env.age;

  services.aurral = {
    enable = true;
    inherit port;
    environmentFile = config.age.secrets.aurral-env.path;

    environment = {
      # Only nginx on loopback sits in front of it.
      TRUST_PROXY = "loopback";
      AURRAL_PUBLIC_URL = "https://${domain}";

      OIDC_ENABLED = "true";
      OIDC_ISSUER = "https://id.shimme.rs/oauth2/openid/aurral";
      OIDC_CLIENT_ID = "aurral";
      OIDC_REDIRECT_URI = "https://${domain}/sso/callback";
      # Who may log in at all is the aurral_users scope map in kanidm.nix.
      OIDC_ADMIN_USERS = "aleph";
      OIDC_DEFAULT_ROLE = "user";
    };
  };

  systemd.services.aurral = {
    after = [ "kanidm.service" ];
    wants = [ "kanidm.service" ];

    # Lidarr reports library files under /mnt/chroma/music; the same path
    # inside aurral's chroot lets it verify and play them. Read-only: imports
    # stay Lidarr's job. No DOWNLOAD_FOLDER on purpose, so aurral's own
    # downloaders (yt-dlp, slskd) have nowhere to write outside the VPN.
    serviceConfig.BindReadOnlyPaths = [ "/mnt/chroma/music" ];
    unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];
  };

  services.nginx.virtualHosts.${domain} = lib.mkMerge [
    (mkProxyHost { inherit port; })
    {
      # Onboarding is unauthenticated until finished (creates the admin and
      # takes arbitrary Lidarr URLs to test), so only allow it over an SSH
      # tunnel straight to the port.
      locations."/api/onboarding".return = "403";
    }
  ];
}
