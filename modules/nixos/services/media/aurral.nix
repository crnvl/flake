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
  # Lidarr's root folder, a read-only folder in aurral.
  libraryFolder = "/mnt/chroma/media/music/library";
  # aurral's own Library folder (its downloadFolderPath setting, in its DB),
  # on the storage box next to Lidarr's rather than inside it, so aurral can
  # clean up and retag its own files. Created once by hand: tmpfiles would
  # touch the automounted storage box early in boot.
  playlistFolder = "/mnt/chroma/media/music/playlists";
  maxWorkerConcurrency = 8;
  workerConcurrency = 6;
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

    # 3.1 rather than nixpkgs' 2.13: 2.x got its metadata from BrainzMash,
    # which now refuses aurral (HTTP 500), and its Last.fm discovery breaks
    # on Dec 1. 3.1 uses AurralBrainz (data.aurral.org) instead
    # (lklynet/aurral#2026). Same build as nixpkgs' 3.0.1, only newer.
    #
    # New users get aurral's playlist section (the accessPlaylists
    # permission) by default: seeing and playing playlists in aurral needs
    # it. It also lets them create flows and import playlists, which download
    # through slskd and SABnzbd. Admins can set this in Settings > Users >
    # Default permissions too, which wins over the built-in default changed
    # here; each new account stores its permissions on creation, so existing
    # accounts are unaffected.
    #
    # aurral-explicit.patch: downloads always take the explicit version. A
    # source named or tagged as the clean/edited version counts as a
    # mismatch, so aurral moves on to the next one; if only clean copies
    # turn up, the track is skipped rather than censored.
    #
    # aurral-worker-queue.patch: the download worker took the next job
    # without checking it could run it. When the head of the queue was
    # already running or waiting for metadata, a free slot fell back to the
    # oldest pending job, and a library track that only waits for a playlist
    # copy deferred itself thousands of times an hour, so a slot spun on it
    # while the playlist queue sat there.
    #
    # The worker's concurrency (how many tracks search and resolve at once)
    # is capped at 3 upstream; raised so a 1000+ track import goes faster.
    # Soulseek searches are still started at most every 5 seconds overall.
    # The value itself is set by aurral-worker-settings below.
    #
    # All are applied to the installed files; tests are skipped since only
    # those change and the rest is upstream's code, tested in nixpkgs.
    package = pkgs.aurral.overrideAttrs (
      finalAttrs: old: {
        version = "3.1.0";
        src = pkgs.fetchFromGitHub {
          owner = "lklynet";
          repo = "aurral";
          tag = "v${finalAttrs.version}";
          hash = "sha256-rORCv0O9OvgfIC4qQeNZMaISu3ciiwecWNTYIQ0NFas=";
        };
        pnpmDeps = old.pnpmDeps.overrideAttrs {
          inherit (finalAttrs) src;
          outputHash = "sha256-o9BTUedHn9nuUPWaXTKSKa/pvEB7Pq2Fw8ehgi6h0RU=";
        };
        doCheck = false;
        postInstall = (old.postInstall or "") + ''
          substituteInPlace $out/lib/aurral/backend/db/helpers/users.ts \
            --replace-fail "accessPlaylists: false," "accessPlaylists: true,"
          substituteInPlace $out/lib/aurral/backend/services/downloadJobs/downloadWorker.ts \
            --replace-fail "const MAX_CONCURRENCY = 3;" "const MAX_CONCURRENCY = ${toString maxWorkerConcurrency};"
          substituteInPlace $out/lib/aurral/backend/routes/playlists/handlers/worker.ts \
            --replace-fail "parsed > 3" "parsed > ${toString maxWorkerConcurrency}" \
            --replace-fail "between 1 and 3" "between 1 and ${toString maxWorkerConcurrency}"
          patch -d $out/lib/aurral -p1 < ${./aurral-explicit.patch}
          patch -d $out/lib/aurral -p1 < ${./aurral-worker-queue.patch}
        '';
      }
    );

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

    # aurral is PID 1 in its private PID namespace, and 3.x runs plugins and
    # downloads as child processes, so something has to reap the orphans
    # (as nixpkgs' newer module does).
    serviceConfig.ExecStart = lib.mkForce "${lib.getExe pkgs.catatonit} -- ${lib.getExe config.services.aurral.package}";

    # Lidarr's root folder. Since 3.0 aurral runs the Library itself and
    # keeps Lidarr's folder as a read-only folder: it plays those files but
    # never renames, retags or deletes them. Albums still come in through
    # Lidarr with the official Lidarr plugin (Settings > Plugins), which
    # hands requests to Lidarr and then finds them in this folder.
    serviceConfig.BindReadOnlyPaths = [ libraryFolder ];
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

  # aurral never searches a failed track again by itself, but Soulseek
  # results change with who is online. Puts every failed playlist track back
  # in the queue once a day. Tracks the user blocked or removed stay alone.
  # The API key lives in aurral's DB (it generates it), hence root and sqlite.
  systemd.services.aurral-retry-failed = {
    description = "re-search failed aurral downloads";
    after = [ "aurral.service" ];
    requires = [ "aurral.service" ];
    startAt = "daily";
    path = with pkgs; [
      curl
      sqlite
    ];
    script = ''
      key="$(sqlite3 -readonly /var/lib/aurral/aurral.db \
        "SELECT json_extract(value, '$.general.apiKey') FROM settings WHERE key = 'integrations'")"
      curl --fail-with-body --silent --show-error --max-time 900 \
        --request POST --header "X-Api-Key: $key" \
        http://127.0.0.1:${toString port}/api/playlists/research-missing
      echo
    '';
    serviceConfig.Type = "oneshot";
  };

  # The worker's concurrency lives in aurral's DB. Set on every aurral start,
  # and daily to undo changes made in the UI (which only offers up to 3).
  systemd.services.aurral-worker-settings = {
    description = "set aurral's download worker concurrency";
    after = [ "aurral.service" ];
    requires = [ "aurral.service" ];
    wantedBy = [ "aurral.service" ];
    startAt = "daily";
    path = with pkgs; [
      curl
      sqlite
    ];
    script = ''
      key="$(sqlite3 -readonly /var/lib/aurral/aurral.db \
        "SELECT json_extract(value, '$.general.apiKey') FROM settings WHERE key = 'integrations'")"
      if [ -z "$key" ]; then
        echo "aurral has no API key yet" >&2
        exit 1
      fi
      curl --fail-with-body --silent --show-error --max-time 60 \
        --retry 30 --retry-delay 2 --retry-connrefused --retry-all-errors \
        --request PUT --header "X-Api-Key: $key" \
        --header "Content-Type: application/json" \
        --data '{"concurrency": ${toString workerConcurrency}}' \
        http://127.0.0.1:${toString port}/api/playlists/worker/settings
      echo
    '';
    serviceConfig.Type = "oneshot";
  };

  # Playback: aurral's Library folder (its playlist folder here) is a second
  # Navidrome library, registered by aurral 2.x. Since 3.0 aurral no longer
  # syncs playlists through Navidrome's API; it writes an M3U per playlist
  # and flow to _playlists in that folder, and Navidrome imports those on
  # its scans. The storage box mount makes everything 0664/0775, so
  # Navidrome can read it despite PrivateUsers (see navidrome.nix).
  systemd.services.navidrome.serviceConfig.BindReadOnlyPaths = [
    "-${playlistFolder}"
  ];

  services.nginx.virtualHosts.${domain} = lib.mkMerge [
    (mkProxyHost { inherit port; })
    {
      # Onboarding is unauthenticated until finished (creates the admin), so
      # only allow it over an SSH tunnel straight to the port.
      locations."/api/onboarding".return = "403";
    }
  ];
}
