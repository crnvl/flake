{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.services.lidarr) dataDir;

  # Tubifarry adds slskd as a Lidarr indexer and download client, so
  # Soulseek results are ranked against the usenet ones by the quality
  # profile (this replaced soularr). Lidarr only loads plugins from
  # plugins/<owner>/<name> in its data dir, and the plugin keeps its own
  # state (settings.resx) next to the DLL, so the folder stays writable and
  # only the release files are put back on every start. That also undoes
  # the update the develop builds install by themselves. Develop builds are
  # the ones for Lidarr 3.1 (master needs 3.2); they report errors to Sentry.
  tubifarry = pkgs.fetchzip {
    url = "https://github.com/TypNull/Tubifarry/releases/download/v2.3.0.2/Tubifarry-v2.3.0.2.net8.0.zip";
    hash = "sha256-Yg4+jJ3LBkBrHs944VXCc/N3hO5e8qM0cRu1ibA2pjA=";
    stripRoot = false;
  };
  tubifarryDir = "${dataDir}/plugins/TypNull/Tubifarry";
  # Albums Search Sniper searched recently, kept across restarts.
  searchSniperCache = "${dataDir}/search-sniper";

  # Lidarr keeps these in its database, so they are pushed through the API.
  #
  # Tags: Lidarr's default is to never write them, so imports kept whatever
  # the Soulseek uploader left in the file. Untagged ones showed up in
  # navidrome as [Unknown Artist], and the rest as near-duplicates ("Health"
  # next to "HEALTH"). "sync" tags every import from MusicBrainz and retags
  # whenever an album's metadata changes. Other tags (lyrics, replaygain)
  # are kept, only the fields Lidarr manages are overwritten.
  #
  # After that, any file whose tags still differ from what Lidarr would
  # write gets retagged: ones imported before the setting, or edited since.
  #
  # Quality: the default profile (root folder and aurral requests) used to
  # take lossless only, so an album nobody had in FLAC never came. Now it
  # takes 256k and better lossy too, and upgrades to lossless when that
  # turns up. Clean/edited versions stay rejected by their custom format.
  #
  # Tubifarry's slskd indexer and download client, plus its Search Sniper.
  # slskd has no RSS, and usenet is search-only in Prowlarr, so after the
  # search on add nothing would look for a missing album again. Search
  # Sniper searches 5 at random every half hour (on all indexers), albums
  # released in the last 30 days first. It also searches albums below the
  # quality cutoff, which is what finds the lossless upgrades. It skips
  # albums it searched in the last week, and pauses while 10 or more
  # downloads are queued.
  #
  # Search: when nothing turns up, try again with more of the album's
  # metadata. Ignore accents and Vol./Volume spellings, and drop folders
  # whose track count is far off.
  #
  # Downloads: give up on a peer that left the album in its upload queue
  # for half an hour, or sent nothing for an hour; Lidarr then blocklists
  # that release and searches again. Only Lidarr's own downloads are
  # tracked, since aurral's playlist downloads share the folder. Album
  # folders left over after import are removed.
  lidarrSettings = pkgs.writeShellApplication {
    name = "lidarr-settings";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = ''
      url=http://localhost:8686/api/v1
      key="''${LIDARR__AUTH__APIKEY:?LIDARR__AUTH__APIKEY is not set}"
      slskd_key="''${SLSKD_API_KEY:?SLSKD_API_KEY is not set}"

      log() { echo "lidarr-settings: $*" >&2; }

      # Lidarr may still be starting up, hence the generous retries.
      api() { # <method> <path> [json body]
        local args=(
          --fail-with-body --silent --show-error --max-time 120
          --retry 30 --retry-delay 2 --retry-connrefused
          --request "$1" --header "X-Api-Key: $key"
        )
        if [ "$#" -ge 3 ]; then
          args+=(--header "Content-Type: application/json" --data-binary "$3")
        fi
        curl "''${args[@]}" "$url/$2"
      }

      # Adds or updates the <kind> (indexer, downloadclient, metadata) of
      # this implementation. The filter adjusts the resource, the object
      # sets fields by name. Saved on every run since Lidarr shows API keys
      # only masked, so a changed one can't be told apart. forceSave skips
      # the connection test, which fails while slskd is still logging in.
      masked='(.fields[] | select(.privacy == "apiKey") | .value) |= "********"'
      provider() { # <kind> <implementation> <jq filter> <fields json>
        local current wanted
        current="$(api GET "$1" | jq -c --arg i "$2" 'first(.[] | select(.implementation == $i)) // empty')"
        if [ -z "$current" ]; then
          current="$(api GET "$1/schema" | jq -c --arg i "$2" 'first(.[] | select(.implementation == $i)) // empty')"
          if [ -z "$current" ]; then
            log "Lidarr has no $1 $2, is Tubifarry loaded?"
            exit 1
          fi
        fi
        wanted="$(jq -c --argjson f "$4" \
          "$3"' | .fields |= map(.name as $n | if $f | has($n) then .value = $f[$n] else . end)' \
          <<< "$current")"
        if [ "$(jq '.id // 0' <<< "$current")" = 0 ]; then
          api POST "$1?forceSave=true" "$wanted" > /dev/null
          log "added $1 $2"
          return
        fi
        api PUT "$1/$(jq -r .id <<< "$current")?forceSave=true" "$wanted" > /dev/null
        if [ "$(jq -S "$masked" <<< "$current")" != "$(jq -S "$masked" <<< "$wanted")" ]; then
          log "updated $1 $2"
        fi
      }

      current="$(api GET config/metadataprovider)"
      wanted="$(jq -c '.writeAudioTags = "sync" | .scrubAudioTags = false' <<< "$current")"
      if [ "$(jq -S . <<< "$current")" != "$(jq -S . <<< "$wanted")" ]; then
        api PUT "config/metadataprovider/$(jq -r .id <<< "$wanted")" "$wanted" > /dev/null
        log "audio tags are now written on import and kept in sync with MusicBrainz"
      fi

      # Found by name, old or new, since ids differ per install. Item ids
      # are Lidarr's quality groups: 1003 Mid (256k), 1004 High (V0/320)
      # and 1005 Lossless.
      current="$(api GET qualityprofile | jq -c \
        'first(.[] | select(.name == "Lossless" or .name == "Lossless preferred")) // empty')"
      if [ -z "$current" ]; then
        log "no Lossless quality profile, leaving quality profiles alone"
      else
        wanted="$(jq -c '
          .name = "Lossless preferred"
          | .upgradeAllowed = true
          | .cutoff = 1005
          | .items |= map(.allowed = ([.id] | inside([1003, 1004, 1005])))
        ' <<< "$current")"
        if [ "$(jq -S . <<< "$current")" != "$(jq -S . <<< "$wanted")" ]; then
          api PUT "qualityprofile/$(jq -r .id <<< "$wanted")" "$wanted" > /dev/null
          log "quality profile $(jq -r .name <<< "$wanted") updated"
        fi
      fi

      slskd="$(jq -nc --arg key "$slskd_key" '{ baseUrl: "http://127.0.0.1:5030", apiKey: $key }')"
      provider downloadclient SlskdClient '.name = "Slskd" | .enable = true' \
        "$(jq -c '. + { timeout: 0.5, inclusive: false, cleanStaleDirectories: true }' <<< "$slskd")"
      provider indexer SlskdIndexer \
        '.name = "Slskd" | .enableRss = false | .enableAutomaticSearch = true | .enableInteractiveSearch = true' \
        "$(jq -c '. + {
          useFallbackSearch: true,
          normalizedSeach: true,
          handleVolumeVariations: true,
          trackCountFilter: 3
        }' <<< "$slskd")"
      provider metadata SearchSniperTask '.enable = true' \
        "$(jq -nc --arg cache ${lib.escapeShellArg searchSniperCache} '{
          refreshInterval: 30,
          randomPicksPerInterval: 5,
          stopWhenQueued: 10,
          requestCacheType: 1,
          cacheDirectory: $cache,
          cacheRetentionDays: 7,
          searchMissing: true,
          searchQualityCutoffNotMet: true,
          prioritizeRecentDays: 30
        }')"

      for artist in $(api GET artist | jq -r '.[].id'); do
        files="$(api GET "retag?artistId=$artist" | jq -c 'map(.trackFileId) | unique')"
        [ "$(jq length <<< "$files")" -gt 0 ] || continue
        api POST command "$(jq -nc --argjson a "$artist" --argjson f "$files" \
          '{ name: "RetagFiles", artistId: $a, files: $f }')" > /dev/null
        log "artist $artist: retagging $(jq length <<< "$files") files"
      done
    '';
  };
in
{
  # Contains LIDARR__AUTH__APIKEY=... so the API key is pinned declaratively
  # and can be shared (aurral-lidarr-webhook reads it) without copying it out
  # of the UI.
  age.secrets.lidarr-env.file = ../../../../hosts/shimmers/secrets/lidarr-env.age;

  services.lidarr = {
    enable = true;
    openFirewall = false;
    environmentFiles = [ config.age.secrets.lidarr-env.path ];
    settings.log.level = "info";
  };

  systemd.services.lidarr = {
    vpnConfinement = {
      enable = true;
      vpnNamespace = "wg";
    };
    unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];

    preStart = ''
      mkdir -p ${lib.escapeShellArg tubifarryDir} ${lib.escapeShellArg searchSniperCache}
      rm -f ${lib.escapeShellArg tubifarryDir}/Lidarr.Plugin.* ${lib.escapeShellArg tubifarryDir}/release_notes.txt
      install -m 0644 ${tubifarry}/* ${lib.escapeShellArg tubifarryDir}/
    '';
  };

  # On every Lidarr start, and daily to undo changes made in the web UI.
  # slskd-env for SLSKD_API_KEY, which Tubifarry's slskd providers use.
  systemd.services.lidarr-settings = {
    description = "apply the Lidarr settings kept in nix and retag drifted files";
    after = [ "lidarr.service" ];
    wantedBy = [ "lidarr.service" ];
    startAt = "daily";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe lidarrSettings;
      EnvironmentFile = [
        config.age.secrets.lidarr-env.path
        config.age.secrets.slskd-env.path
      ];
      DynamicUser = true;
    };
  };

  my.vpn.confinedServices = [ "lidarr-settings" ];

  # media: /mnt/chroma library, sabnzbd/qbittorrent downloads, and the slskd
  # downloads dir (setgid media, see slskd.nix) so imports can move files out.
  users.users.lidarr.extraGroups = [ "media" ];

  my.vpn.portMappings = [
    {
      from = 8686;
      to = 8686;
    }
  ];
}
