{
  config,
  lib,
  mkProxyHost,
  ...
}:

let
  domain = "aurral.shimme.rs";
  port = 3001;
  # aurral's fallback download folder (no DOWNLOAD_FOLDER set), also what it
  # has stored as downloadFolderPath.
  playlistFolder = "${config.services.aurral.dataDir}/downloads/aurral";
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
    # stay Lidarr's job.
    serviceConfig.BindReadOnlyPaths = [ "/mnt/chroma/music" ];
    # Playlist downloads go through slskd and SABnzbd, which download inside
    # the VPN namespace; aurral then moves (and retags) the finished files
    # into its own download folder under /var/lib/aurral. Those dirs are
    # group-writable by media, and the sources point at the namespace
    # address (192.168.15.1) from aurral's settings, which live in its DB.
    #
    # yt-dlp is switched off in those settings on purpose: aurral runs on the
    # host network, so it would download straight from this machine's IP.
    # (Leaving DOWNLOAD_FOLDER unset does not stop it, aurral just falls back
    # to a folder under its data dir.)
    serviceConfig.SupplementaryGroups = [ "media" ];
    unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];
  };

  services.aurral.directories = [
    config.services.slskd.settings.directories.downloads
    "/var/lib/sabnzbd/downloads/aurral"
  ];

  # Playback: aurral registers its download folder as a second Navidrome
  # library, by the path it sees it under, and syncs its playlists into it.
  # Its Navidrome URL (in its settings) is http://127.0.0.1:4533 rather than
  # music.shimme.rs: the public vhost sits behind oauth2-proxy, which turns
  # aurral's API login into a redirect. Navidrome only trusts the Remote-User
  # header when it is actually sent, so a plain password login from loopback
  # still works. Streams are proxied by aurral's backend, so the loopback URL
  # never reaches a browser.
  systemd.services.navidrome.serviceConfig.BindReadOnlyPaths = [
    "-${playlistFolder}"
  ];

  # Navidrome runs with PrivateUsers=true, so group access is out (see
  # navidrome.nix), and aurral writes 0660/0770 by design: its data dir holds
  # its database, encryption key included. A named-user ACL works under
  # PrivateUsers, and the default entry makes new files and folders inherit
  # it. Applied when the folder exists (aurral creates it on first start).
  systemd.tmpfiles.rules = [
    "A+ ${playlistFolder} - - - - u:navidrome:r-x,d:u:navidrome:r-x"
  ];

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
