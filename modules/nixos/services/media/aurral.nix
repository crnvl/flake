{
  config,
  lib,
  pkgs,
  mkProxyHost,
  ...
}:

let
  domain = "aurral.shimme.rs";
  port = 3001;
  # On the storage box next to media/music, not on the system disk. aurral
  # has this stored as its downloadFolderPath (settings, in its DB). The
  # folder itself was created once by hand: tmpfiles would touch the
  # automounted storage box early in boot.
  playlistFolder = "/mnt/chroma/media/aurral";
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

    # New users get aurral's playlist section (the accessFlow permission) by
    # default: seeing and playing playlists in aurral needs it. It also lets
    # them create flows and import playlists, which download through slskd
    # and SABnzbd. aurral has no setting for new users' permissions, so this
    # flips the built-in default; each new account stores its permissions on
    # creation, so existing accounts are unaffected. Tests are skipped since
    # only the installed default changes; the code is upstream's, tested in
    # nixpkgs.
    package = pkgs.aurral.overrideAttrs (old: {
      doCheck = false;
      postInstall = (old.postInstall or "") + ''
        substituteInPlace $out/lib/node_modules/aurral/backend/db/helpers/users.js \
          --replace-fail "accessFlow: false," "accessFlow: true,"
      '';
    });

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

      # SABnzbd reports its completed folder as "downloads", relative to its
      # own data dir; aurral would resolve that against its own working dir.
      # Point it at the aurral category folder (the one bound in below), so
      # the storage health check tests the folder aurral actually works in.
      # Real jobs are unaffected: SABnzbd's history gives absolute paths,
      # which exist here and are never remapped.
      PATH_MAPPINGS = "sabnzbd|downloads|/var/lib/sabnzbd/downloads/aurral";
    };
  };

  systemd.services.aurral = {
    after = [ "kanidm.service" ];
    wants = [ "kanidm.service" ];

    # Lidarr reports library files under /mnt/chroma/media/music; the same
    # path inside aurral's chroot lets it verify and play them. Read-only:
    # imports stay Lidarr's job.
    serviceConfig.BindReadOnlyPaths = [ "/mnt/chroma/media/music" ];
    # Playlist downloads go through slskd and SABnzbd, which download inside
    # the VPN namespace; aurral then moves (and retags) the finished files
    # into its playlist folder on the storage box. The download dirs are
    # group-writable by media, as is everything on the storage box mount,
    # and the sources point at the namespace address (192.168.15.1) from
    # aurral's settings, which live in its DB.
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
    playlistFolder
  ];

  # Playback: aurral registers its playlist folder as a second Navidrome
  # library, by the path it sees it under, and syncs its playlists into it.
  # Its Navidrome URL (in its settings) is http://127.0.0.1:4533 rather than
  # music.shimme.rs: the public vhost sits behind oauth2-proxy, which turns
  # aurral's API login into a redirect. Navidrome only trusts the Remote-User
  # header when it is actually sent, so a plain password login from loopback
  # still works. Streams are proxied by aurral's backend, so the loopback URL
  # never reaches a browser. The storage box mount makes everything 0664/0775,
  # so Navidrome can read it despite PrivateUsers (see navidrome.nix).
  systemd.services.navidrome.serviceConfig.BindReadOnlyPaths = [
    "-${playlistFolder}"
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
