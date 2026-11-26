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
  # On the storage box under media/music, next to Lidarr's library rather
  # than inside it: aurral leaves anything in a Lidarr root folder alone, so
  # it would never clean up or retag its own files there. aurral has this
  # stored as its downloadFolderPath (settings, in its DB). The folder itself
  # was created once by hand: tmpfiles would touch the automounted storage
  # box early in boot.
  libraryFolder = "/mnt/chroma/media/music/library";
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

    # New users get aurral's playlist section (the accessFlow permission) by
    # default: seeing and playing playlists in aurral needs it. It also lets
    # them create flows and import playlists, which download through slskd
    # and SABnzbd. aurral has no setting for new users' permissions, so this
    # flips the built-in default; each new account stores its permissions on
    # creation, so existing accounts are unaffected.
    #
    # aurral-explicit.patch: downloads always take the explicit version. A
    # source named or tagged as the clean/edited version counts as a
    # mismatch, so aurral moves on to the next one; if only clean copies
    # turn up, the track is skipped rather than censored.
    #
    # aurral-album-artist-path.patch: an album requested from one artist's
    # page can belong to another MusicBrainz artist. Lidarr adds that one
    # from the requesting artist's settings, and aurral used to send the
    # folder along, so What So Not ended up in "Buunshin (1)".
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
    # Stopgap until aurral is on 3.1+: BrainzMash, the metadata server 2.x
    # uses, now answers aurral with HTTP 500 (upstream moved to its own server,
    # lklynet/aurral#2026). A track whose album can't be read waited 30
    # minutes for it before searching, so the whole queue crawled. Now it
    # searches right away and matches on artist, title and duration.
    #
    # All are applied to the installed files; tests are skipped since only
    # those change and the rest is upstream's code, tested in nixpkgs.
    package = pkgs.aurral.overrideAttrs (old: {
      doCheck = false;
      postInstall = (old.postInstall or "") + ''
        substituteInPlace $out/lib/aurral/backend/db/helpers/users.ts \
          --replace-fail "accessFlow: false," "accessFlow: true,"
        substituteInPlace $out/lib/aurral/backend/services/downloadJobs/downloadWorker.ts \
          --replace-fail "const MAX_CONCURRENCY = 3;" "const MAX_CONCURRENCY = ${toString maxWorkerConcurrency};"
        substituteInPlace $out/lib/aurral/backend/routes/playlists/handlers/worker.ts \
          --replace-fail "parsed > 3" "parsed > ${toString maxWorkerConcurrency}" \
          --replace-fail "between 1 and 3" "between 1 and ${toString maxWorkerConcurrency}"
        substituteInPlace $out/lib/aurral/backend/services/releaseResolver.ts \
          --replace-fail "export const MAX_RELEASE_WAITS = 30;" "export const MAX_RELEASE_WAITS = 0;"
        patch -d $out/lib/aurral -p1 < ${./aurral-explicit.patch}
        patch -d $out/lib/aurral -p1 < ${./aurral-album-artist-path.patch}
        patch -d $out/lib/aurral -p1 < ${./aurral-worker-queue.patch}
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

    # Lidarr reports library files under its root folder; the same path
    # inside aurral's chroot lets it verify and play them. Read-only:
    # imports stay Lidarr's job.
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

  # Lidarr tells aurral about every import. That's the only way a requested
  # album gets marked available in aurral's request history (and its
  # "Request available" notification goes out). Lidarr sits in the VPN
  # namespace and can't open connections to the host, so it goes through
  # the public vhost. Runs as root to read aurral's API key from its DB
  # (like aurral-retry-failed), inside the namespace to reach Lidarr, and
  # like lidarr-settings on every Lidarr start and daily to undo UI edits.
  systemd.services.aurral-lidarr-webhook = {
    description = "point Lidarr's import webhook at aurral";
    after = [
      "aurral.service"
      "lidarr.service"
    ];
    wants = [ "aurral.service" ];
    wantedBy = [ "lidarr.service" ];
    startAt = "daily";
    path = with pkgs; [
      curl
      jq
      sqlite
    ];
    script = ''
      aurral_key="$(sqlite3 -readonly /var/lib/aurral/aurral.db \
        "SELECT json_extract(value, '$.general.apiKey') FROM settings WHERE key = 'integrations'")"
      if [ -z "$aurral_key" ]; then
        echo "aurral has no API key yet" >&2
        exit 1
      fi
      hook=https://${domain}/api/webhooks/lidarr

      api() { # <method> <path> [json body]
        local args=(
          --fail-with-body --silent --show-error --max-time 60
          --retry 30 --retry-delay 2 --retry-connrefused
          --request "$1" --header "X-Api-Key: $LIDARR__AUTH__APIKEY"
        )
        if [ "$#" -ge 3 ]; then
          args+=(--header "Content-Type: application/json" --data-binary "$3")
        fi
        curl "''${args[@]}" "http://localhost:8686/api/v1/$2"
      }

      current="$(api GET notification | jq -c --arg u "$hook" \
        'first(.[] | select(.implementation == "Webhook" and any(.fields[]; .name == "url" and .value == $u))) // empty')"
      [ -n "$current" ] || current="$(api GET notification/schema | jq -c 'first(.[] | select(.implementation == "Webhook"))')"
      wanted="$(jq -c --arg u "$hook" --arg k "$aurral_key" '
        .name = "aurral"
        | with_entries(if (.key | test("^on[A-Z]")) then .value = (.key == "onReleaseImport") else . end)
        | .fields |= map(
            if .name == "url" then .value = $u
            elif .name == "method" then .value = 1
            elif .name == "headers" then .value = [{ key: "X-Api-Key", value: $k }]
            else . end)
      ' <<< "$current")"
      if [ "$(jq '.id // 0' <<< "$current")" = 0 ]; then
        api POST "notification?forceSave=true" "$wanted" > /dev/null
        echo "added the aurral webhook"
      elif [ "$(jq -S . <<< "$current")" != "$(jq -S . <<< "$wanted")" ]; then
        api PUT "notification/$(jq -r .id <<< "$current")?forceSave=true" "$wanted" > /dev/null
        echo "updated the aurral webhook"
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.age.secrets.lidarr-env.path;
    };
  };

  my.vpn.confinedServices = [ "aurral-lidarr-webhook" ];

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
