{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.mediaJanitor;

  helpText = pkgs.writeText "media-janitor-help.txt" ''
    media-janitor - evict media nobody is watching and free the storage box

    usage: media-janitor [options]

      --delete        actually remove things; without this it is a dry run
      --json          print the full policy report as JSON and exit
      --no-webhook    do not post the result to discord
      -h, --help      this text

    Reads per-user watch data from jellyfin and evicts movies and series that
    are stale (last played by anyone too long ago) or that were never played
    and have sat on disk long enough. Whole series are the unit of removal, so
    recent activity anywhere in a show protects all of its seasons; abandoned
    view progress does not. Jellyfin favorites are never touched, and neither
    is anything added recently. Eviction deletes the files through radarr and
    sonarr (without import exclusions) and drops the seerr media entry, so
    everything can be re-requested later.

    Needs to run as root: the seerr api key lives in its state directory and
    the other keys are agenix secrets.
  '';

  # Joins jellyfin watch data (aggregated across all users) with radarr,
  # sonarr and seerr state, applies the retention policy and emits the
  # removal candidates, most stale first, capped at $maxPerRun.
  policyScript = pkgs.writeText "media-janitor-policy.jq" ''
    # Jellyfin timestamps carry 7-digit fractional seconds, which
    # fromdateiso8601 refuses, so strip them (and normalise the zone) first.
    def ts:
      if . == null or . == "" then null
      else
        ( tostring
          | gsub("\\.[0-9]+"; "")
          | sub("\\+00:00$"; "Z")
          | (if endswith("Z") then . else . + "Z" end)
          | (fromdateiso8601? // null)
        )
      end;

    def verdict($now; $minAge; $unwatched; $retention):
      if .favorite then "favorite"
      elif .arr == null then "unmanaged"
      elif .added == null then "undated"
      elif ($now - .added) < ($minAge * 86400) then "added recently"
      elif .lastPlayed == null then
        (if ($now - .added) >= ($unwatched * 86400)
         then "remove: never watched"
         else "unwatched, waiting" end)
      elif ($now - .lastPlayed) >= ($retention * 86400)
      then "remove: gone stale"
      else "watched recently" end;

    ($jfItems[0] // []) as $items
    | ($jfEpisodes[0] // []) as $episodes
    | ($radarr[0] // []) as $radarrMovies
    | ($sonarr[0] // []) as $sonarrSeries
    | ($seerr[0] // []) as $seerrMedia
    | now as $now
    | ($radarrMovies
        | map(select(.tmdbId != null)
          | { key: (.tmdbId | tostring), value: { id: .id, size: (.sizeOnDisk // 0) } })
        | from_entries
      ) as $radarrByTmdb
    | ($sonarrSeries
        | map(select(.tvdbId != null)
          | { key: (.tvdbId | tostring), value: { id: .id, size: (.statistics.sizeOnDisk // 0) } })
        | from_entries
      ) as $sonarrByTvdb
    | ($seerrMedia
        | map(select(.mediaType == "movie" and .tmdbId != null))
        | group_by(.tmdbId)
        | map({ key: (.[0].tmdbId | tostring), value: map(.id) })
        | from_entries
      ) as $seerrByTmdb
    | ($seerrMedia
        | map(select(.mediaType == "tv" and .tvdbId != null))
        | group_by(.tvdbId)
        | map({ key: (.[0].tvdbId | tostring), value: map(.id) })
        | from_entries
      ) as $seerrByTvdb
    # One row per user per item comes in; fold to one per item. Any recent
    # play by anyone protects it, any favorite mark by anyone protects it.
    | ($items
        | map(select(.type == "Movie"))
        | group_by(.id)
        | map({
            title: .[0].name,
            key: (.[0].tmdb // null),
            added: (map(.added | ts) | max),
            lastPlayed: (map(.lastPlayed | ts) | max),
            favorite: (map(.favorite) | any)
          })
      ) as $movies
    # Series activity and freshness live on the episodes: the newest episode
    # DateCreated keeps shows with a freshly added season out of reach, and
    # the newest LastPlayedDate across all users and seasons is what "actively
    # watching" means.
    | ($episodes
        | map(select(.series != null))
        | group_by(.series)
        | map({
            key: .[0].series,
            value: {
              lastPlayed: (map(.lastPlayed | ts) | max),
              lastAdded: (map(.added | ts) | max)
            }
          })
        | from_entries
      ) as $epBySeries
    | ($items
        | map(select(.type == "Series"))
        | group_by(.id)
        | map(
            ($epBySeries[.[0].id] // { lastPlayed: null, lastAdded: null }) as $ep
            | {
                title: .[0].name,
                key: (.[0].tvdb // null),
                added: ([ (map(.added | ts) | max), $ep.lastAdded ] | max),
                lastPlayed: $ep.lastPlayed,
                favorite: (map(.favorite) | any)
              }
          )
      ) as $series
    | ( [ $movies[]
          | . + { type: "movie",
                  arr: (if .key == null then null else ($radarrByTmdb[.key | tostring] // null) end),
                  seerrIds: (if .key == null then [] else ($seerrByTmdb[.key | tostring] // []) end) } ]
        + [ $series[]
          | . + { type: "series",
                  arr: (if .key == null then null else ($sonarrByTvdb[.key | tostring] // null) end),
                  seerrIds: (if .key == null then [] else ($seerrByTvdb[.key | tostring] // []) end) } ]
      )
    | map(. + { verdict: verdict($now; $minAgeDays; $unwatchedAfterDays; $watchedRetentionDays) }) as $all
    | ($all
        | map(select(.verdict | startswith("remove")))
        | sort_by(.lastPlayed // .added)
      ) as $due
    | $due[0:$maxPerRun] as $chosen
    | {
        generated: ($now | todate),
        thresholds: {
          minAgeDays: $minAgeDays,
          unwatchedAfterDays: $unwatchedAfterDays,
          watchedRetentionDays: $watchedRetentionDays,
          maxPerRun: $maxPerRun
        },
        verdicts: ($all | group_by(.verdict) | map({ key: .[0].verdict, value: length }) | from_entries),
        deferred: (($due | length) - ($chosen | length)),
        totalSize: ($chosen | map(.arr.size) | add // 0),
        candidates: ($chosen | map({
            type: .type,
            title: .title,
            arrId: .arr.id,
            size: .arr.size,
            seerrIds: .seerrIds,
            reason: (if .lastPlayed == null
                     then "never watched, added \(.added | todate | .[0:10])"
                     else "last watched \(.lastPlayed | todate | .[0:10])" end),
            idleDays: ((($now - (.lastPlayed // .added)) / 86400) | floor)
          }))
      }
  '';

  # Turns the run outcome into a discord webhook payload.
  embedScript = pkgs.writeText "media-janitor-embed.jq" ''
    def human:
      (. // 0) as $b
      | if $b < 1024 then "\($b | floor) B"
        else
          ([ range(1; 7) ] | map(select(pow(1024; .) <= $b)) | last) as $i
          | ((($b / pow(1024; $i)) * 10 | round) / 10) as $v
          | "\($v) \([ "B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB" ][$i])"
        end;

    .removed as $r
    | (.failed // []) as $failed
    | ($r | map(.size // 0) | add // 0) as $bytes
    | ($r
        | map("**\(.title)**\(if .type == "series" then " (series)" else "" end) — \(.size | human), \(.reason)")
        | join("\n")
        | .[0:3900]
      ) as $lines
    | ([ (if .deferred > 0 then "\(.deferred) more over the limit, due next run" else empty end),
         (if ($failed | length) > 0 then "FAILED to remove: \($failed | join(", "))" else empty end),
         (if .dryRun then "dry run — nothing was actually deleted" else empty end)
       ] | join(" · ")) as $foot
    | {
        username: "media janitor",
        embeds: [
          ( {
              title: (if .dryRun
                      then "would remove \($r | length) items, freeing \($bytes | human)"
                      else "removed \($r | length) items, freed \($bytes | human)" end),
              color: (if .dryRun then 16426522 else 15092822 end),
              description: $lines
            }
            + (if $foot == "" then {} else { footer: { text: $foot } } end)
          )
        ]
      }
  '';

  janitorScript = pkgs.writeShellApplication {
    name = "media-janitor";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      iproute2
      jq
    ];
    text = ''
      jellyfin_url=${lib.escapeShellArg cfg.jellyfinUrl}
      seerr_url=${lib.escapeShellArg cfg.seerrUrl}
      radarr_url=${lib.escapeShellArg cfg.radarrUrl}
      sonarr_url=${lib.escapeShellArg cfg.sonarrUrl}
      arr_ns=${lib.escapeShellArg (if cfg.arrNamespace == null then "" else cfg.arrNamespace)}
      settings=${lib.escapeShellArg (toString cfg.settingsFile)}
      jellyfin_key_file=${lib.escapeShellArg (toString cfg.jellyfinKeyFile)}
      radarr_key_file=${lib.escapeShellArg (toString cfg.radarrKeyFile)}
      sonarr_key_file=${lib.escapeShellArg (toString cfg.sonarrKeyFile)}
      webhook_file=${lib.escapeShellArg (toString cfg.discordWebhookFile)}
      min_age=${toString cfg.minAgeDays}
      unwatched_after=${toString cfg.unwatchedAfterDays}
      watched_retention=${toString cfg.watchedRetentionDays}
      max_per_run=${toString cfg.maxPerRun}

      delete=false
      as_json=false
      webhook=true

      usage() { cat ${helpText}; }
      die() { echo "media-janitor: $*" >&2; exit 1; }

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --delete) delete=true ;;
          --dry-run) delete=false ;;
          --json) as_json=true ;;
          --no-webhook) webhook=false ;;
          -h|--help) usage; exit 0 ;;
          *) usage >&2; die "unknown argument $1" ;;
        esac
        shift
      done

      [ -r "$settings" ] || die "cannot read $settings, run this as root"
      seerr_key="$(jq -r '.main.apiKey // empty' "$settings")"
      [ -n "$seerr_key" ] || die "no main.apiKey in $settings"

      read_key() {
        [ -r "$1" ] || die "cannot read the $2 key at $1, run this as root"
        tr -d '[:space:]' < "$1"
      }

      jellyfin_key="$(read_key "$jellyfin_key_file" jellyfin)"
      radarr_key="$(read_key "$radarr_key_file" radarr)"
      sonarr_key="$(read_key "$sonarr_key_file" sonarr)"
      webhook_url=""
      if [ "$webhook" = true ]; then
        webhook_url="$(read_key "$webhook_file" "discord webhook")"
      fi

      # radarr and sonarr live in the vpn namespace and their port mappings
      # are PREROUTING DNAT rules, which locally generated packets never
      # traverse, so ask from inside the namespace, like seerr-usage does.
      if [ -n "$arr_ns" ] && [ ! -e "/run/netns/$arr_ns" ]; then
        echo "media-janitor: no $arr_ns namespace, trying the host network instead" >&2
        arr_ns=""
      fi

      curl_opts=(
        --fail --silent --show-error --location --max-time 120
        --retry 2 --retry-delay 2 --retry-all-errors
      )

      jf_get() { curl "''${curl_opts[@]}" --header "X-Emby-Token: $jellyfin_key" "$1"; }
      jf_post() { curl "''${curl_opts[@]}" --request POST --header "X-Emby-Token: $jellyfin_key" "$1"; }
      seerr_get() { curl "''${curl_opts[@]}" --header "X-Api-Key: $seerr_key" "$1"; }
      seerr_del() { curl "''${curl_opts[@]}" --request DELETE --header "X-Api-Key: $seerr_key" "$1"; }

      arr_curl() {
        if [ -n "$arr_ns" ]; then
          ip netns exec "$arr_ns" curl "''${curl_opts[@]}" "$@"
        else
          curl "''${curl_opts[@]}" "$@"
        fi
      }
      arr_get() { arr_curl --header "X-Api-Key: $2" "$1"; }
      arr_del() { arr_curl --request DELETE --header "X-Api-Key: $2" "$1"; }

      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      # -- gather ------------------------------------------------------------

      users="$(jf_get "$jellyfin_url/Users")" || die "jellyfin unreachable at $jellyfin_url"
      mapfile -t user_ids < <(jq -r '.[].Id' <<< "$users")
      [ "''${#user_ids[@]}" -gt 0 ] || die "jellyfin returned no users, refusing to act on empty watch data"

      item_proj='{type: .Type, id: .Id, name: .Name,
                  tmdb: .ProviderIds.Tmdb, tvdb: .ProviderIds.Tvdb,
                  added: .DateCreated, lastPlayed: .UserData.LastPlayedDate,
                  favorite: (.UserData.IsFavorite // false)}'
      episode_proj='{series: .SeriesId, added: .DateCreated, lastPlayed: .UserData.LastPlayedDate}'

      jf_page() { # user-id item-types fields outfile projection
        local start=0 take=1000 page count
        while : ; do
          page="$(jf_get "$jellyfin_url/Items?userId=$1&IncludeItemTypes=$2&Recursive=true&Fields=$3&EnableUserData=true&EnableImages=false&Limit=$take&StartIndex=$start")" \
            || die "jellyfin item listing failed for user $1"
          count="$(jq '.Items | length' <<< "$page")"
          jq -c ".Items[] | $5" <<< "$page" >> "$4"
          if [ "$count" -lt "$take" ]; then
            break
          fi
          start=$(( start + take ))
        done
      }

      : > "$tmp/items.jsonl"
      : > "$tmp/episodes.jsonl"
      for uid in "''${user_ids[@]}"; do
        jf_page "$uid" "Movie,Series" "ProviderIds,DateCreated" "$tmp/items.jsonl" "$item_proj"
        jf_page "$uid" "Episode" "DateCreated" "$tmp/episodes.jsonl" "$episode_proj"
      done
      [ -s "$tmp/items.jsonl" ] || die "jellyfin returned no items, refusing to act on empty watch data"
      jq -s '.' "$tmp/items.jsonl" > "$tmp/items.json"
      jq -s '.' "$tmp/episodes.jsonl" > "$tmp/episodes.json"

      # Unlike seerr-usage this tool deletes things, so a dead API is a hard
      # stop rather than a zero-sized column.
      radarr_movies="$(arr_get "$radarr_url/api/v3/movie" "$radarr_key")" || die "radarr unreachable at $radarr_url"
      printf '%s' "$radarr_movies" > "$tmp/radarr.json"
      sonarr_series="$(arr_get "$sonarr_url/api/v3/series" "$sonarr_key")" || die "sonarr unreachable at $sonarr_url"
      printf '%s' "$sonarr_series" > "$tmp/sonarr.json"

      : > "$tmp/seerr.jsonl"
      skip=0
      take=100
      while : ; do
        page="$(seerr_get "$seerr_url/api/v1/media?take=$take&skip=$skip&sort=added")" \
          || die "seerr unreachable at $seerr_url"
        count="$(jq '.results | length' <<< "$page")"
        jq -c '.results[] | {id, mediaType, tmdbId, tvdbId}' <<< "$page" >> "$tmp/seerr.jsonl"
        if [ "$count" -lt "$take" ]; then
          break
        fi
        skip=$(( skip + take ))
      done
      jq -s '.' "$tmp/seerr.jsonl" > "$tmp/seerr.json"

      # -- decide ------------------------------------------------------------

      report="$(jq -n \
        --slurpfile jfItems "$tmp/items.json" \
        --slurpfile jfEpisodes "$tmp/episodes.json" \
        --slurpfile radarr "$tmp/radarr.json" \
        --slurpfile sonarr "$tmp/sonarr.json" \
        --slurpfile seerr "$tmp/seerr.json" \
        --argjson minAgeDays "$min_age" \
        --argjson unwatchedAfterDays "$unwatched_after" \
        --argjson watchedRetentionDays "$watched_retention" \
        --argjson maxPerRun "$max_per_run" \
        -f ${policyScript})"

      if [ "$as_json" = true ]; then
        jq '.' <<< "$report"
        exit 0
      fi

      count="$(jq '.candidates | length' <<< "$report")"
      if [ "$count" -eq 0 ]; then
        echo "media-janitor: nothing to remove"
        jq -r '.verdicts | to_entries[] | "  \(.value) \(.key)"' <<< "$report"
        exit 0
      fi

      # -- act ---------------------------------------------------------------

      : > "$tmp/removed.jsonl"
      : > "$tmp/failed.txt"

      if [ "$delete" = true ]; then
        while read -r candidate; do
          ctype="$(jq -r '.type' <<< "$candidate")"
          arr_id="$(jq -r '.arrId' <<< "$candidate")"
          title="$(jq -r '.title' <<< "$candidate")"
          if [ "$ctype" = movie ]; then
            ok=true
            arr_del "$radarr_url/api/v3/movie/$arr_id?deleteFiles=true&addImportExclusion=false" "$radarr_key" > /dev/null || ok=false
          else
            ok=true
            arr_del "$sonarr_url/api/v3/series/$arr_id?deleteFiles=true&addImportListExclusion=false" "$sonarr_key" > /dev/null || ok=false
          fi
          if [ "$ok" = true ]; then
            printf '%s\n' "$candidate" >> "$tmp/removed.jsonl"
            # Dropping the media entry also drops its requests, resetting the
            # title to "unknown" in seerr so it can be requested again.
            while read -r sid; do
              [ -n "$sid" ] || continue
              seerr_del "$seerr_url/api/v1/media/$sid" > /dev/null \
                || echo "media-janitor: seerr media $sid ($title) was already gone" >&2
            done < <(jq -r '.seerrIds[]' <<< "$candidate")
            echo "media-janitor: removed $ctype $title"
          else
            printf '%s\n' "$title" >> "$tmp/failed.txt"
            echo "media-janitor: FAILED to remove $ctype $title (arr id $arr_id)" >&2
          fi
        done < <(jq -c '.candidates[]' <<< "$report")

        if [ -s "$tmp/removed.jsonl" ]; then
          # Refresh before seerr's next availability sync, so it does not
          # re-mark the deleted entries as available from stale library data.
          jf_post "$jellyfin_url/Library/Refresh" > /dev/null \
            || echo "media-janitor: could not trigger a jellyfin library refresh" >&2
        fi
      else
        jq -c '.candidates[]' <<< "$report" > "$tmp/removed.jsonl"
        echo "media-janitor: dry run, would remove:"
        jq -r '.candidates[] | "  \(.title) [\(.type)] — \(((.size // 0) / 1073741824 * 10 | round) / 10) GiB, \(.reason)"' <<< "$report"
      fi

      jq -s '.' "$tmp/removed.jsonl" > "$tmp/removed.json"
      jq -R -s 'split("\n") | map(select(. != ""))' "$tmp/failed.txt" > "$tmp/failed.json"

      # -- report ------------------------------------------------------------

      if [ "$delete" = true ]; then dry_json=false; else dry_json=true; fi
      outcome="$(jq -n \
        --argjson dryRun "$dry_json" \
        --argjson deferred "$(jq '.deferred' <<< "$report")" \
        --slurpfile removed "$tmp/removed.json" \
        --slurpfile failed "$tmp/failed.json" \
        '{ dryRun: $dryRun, deferred: $deferred,
           removed: ($removed[0] // []), failed: ($failed[0] // []) }')"

      if [ "$webhook" = true ]; then
        payload="$(jq -f ${embedScript} <<< "$outcome")"
        curl "''${curl_opts[@]}" --request POST \
          --header 'Content-Type: application/json' \
          --data "$payload" "$webhook_url" > /dev/null \
          || die "the discord webhook did not accept the report"
      fi

      if [ -s "$tmp/failed.txt" ]; then
        die "some removals failed, see above"
      fi
    '';
  };
in
{
  options.my.mediaJanitor = {
    jellyfinUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8096";
      description = "Base URL of jellyfin, the source of per-user watch data.";
    };

    seerrUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:${toString config.services.seerr.port}";
      defaultText = lib.literalExpression ''"http://localhost:''${toString config.services.seerr.port}"'';
      description = "Base URL of the seerr instance whose media entries get dropped.";
    };

    radarrUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:7878";
      description = "Base URL of radarr, which deletes the movie files.";
    };

    sonarrUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8989";
      description = "Base URL of sonarr, which deletes the series files.";
    };

    arrNamespace = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "wg";
      description = ''
        Network namespace to run the radarr and sonarr queries in, see
        seerr-usage for why. Set to null to use the host network instead.
      '';
    };

    minAgeDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = ''
        Grace period: nothing added to the library within this many days is
        ever touched, no matter its watch state. For series the clock restarts
        whenever a new episode lands.
      '';
    };

    unwatchedAfterDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = "Remove media never played by anyone once it is this many days old.";
    };

    watchedRetentionDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 90;
      description = ''
        Remove media whose most recent play by anyone lies further back than
        this. Any playback activity counts, including partial ones, so a
        series someone is actively working through stays, while abandoned
        view progress does not protect anything.
      '';
    };

    maxPerRun = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = ''
        Safety cap on removals per run. The most stale items go first and the
        rest waits for the next run, so a bad API answer or misconfiguration
        cannot wipe the whole library in one night.
      '';
    };

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        While true the timer only reports what it would remove, both to the
        journal and to discord. Set to false once the verdicts look sane.
      '';
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-01 05:00:00";
      description = "When the timer fires, systemd.time(7) syntax.";
    };

    settingsFile = lib.mkOption {
      type = lib.types.path;
      default = "${lib.removeSuffix "/" (toString config.services.seerr.configDir)}/settings.json";
      defaultText = lib.literalExpression ''"''${config.services.seerr.configDir}/settings.json"'';
      description = "Seerr's settings file, which is where its API key lives.";
    };

    jellyfinKeyFile = lib.mkOption {
      type = lib.types.path;
      default = config.age.secrets.jellyfin-api-key.path;
      defaultText = lib.literalExpression "config.age.secrets.jellyfin-api-key.path";
      description = "File holding a jellyfin admin API key.";
    };

    radarrKeyFile = lib.mkOption {
      type = lib.types.path;
      default = config.age.secrets.radarr-api-key.path;
      defaultText = lib.literalExpression "config.age.secrets.radarr-api-key.path";
      description = "File holding the radarr API key.";
    };

    sonarrKeyFile = lib.mkOption {
      type = lib.types.path;
      default = config.age.secrets.sonarr-api-key.path;
      defaultText = lib.literalExpression "config.age.secrets.sonarr-api-key.path";
      description = "File holding the sonarr API key.";
    };

    discordWebhookFile = lib.mkOption {
      type = lib.types.path;
      default = config.age.secrets.media-janitor-webhook.path;
      defaultText = lib.literalExpression "config.age.secrets.media-janitor-webhook.path";
      description = "File holding the discord webhook URL to post removal reports to.";
    };
  };

  config = {
    age.secrets = {
      radarr-api-key.file = ../../../../hosts/shimmers/secrets/radarr-api-key.age;
      sonarr-api-key.file = ../../../../hosts/shimmers/secrets/sonarr-api-key.age;
      jellyfin-api-key.file = ../../../../hosts/shimmers/secrets/jellyfin-api-key.age;
      media-janitor-webhook.file = ../../../../hosts/shimmers/secrets/media-janitor-webhook.age;
    };

    environment.systemPackages = [ janitorScript ];

    systemd.services.media-janitor = {
      description = "evict stale media and its arr/seerr tracking";
      after = [
        "network-online.target"
        "jellyfin.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.concatStringsSep " " (
          [ "${janitorScript}/bin/media-janitor" ] ++ lib.optional (!cfg.dryRun) "--delete"
        );
      };
    };

    systemd.timers.media-janitor = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
    };
  };
}
