{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.mediaJanitor;

  helpText = pkgs.writeText "media-janitor-help.txt" ''
    media-janitor - evict the least watched media and free the storage box

    usage: media-janitor [options]

      --delete        actually remove things; without this it is a dry run
      --ranking       print the full ranking and exit
      --json          print the full policy report as JSON and exit
      --no-webhook    do not post the result to discord
      -h, --help      this text

    Reads per-user watch data from jellyfin and ranks every movie and series
    by its most recent sign of life: the last time anyone played it, or the
    last time something landed on disk for it (a fresh request, a new
    season), whichever is newer. The bottom ${toString cfg.removePercent}% of that ranking gets
    evicted. Whole series are the unit of removal, so recent activity
    anywhere in a show lifts all of its seasons. Jellyfin favorites and
    anything added in the last ${toString cfg.minAgeDays} days are left out of the ranking
    entirely. Eviction deletes the files through radarr and sonarr (without
    import exclusions) and drops the seerr media entry, so everything can be
    re-requested later.

    Needs to run as root: the seerr api key lives in its state directory and
    the other keys are agenix secrets.
  '';

  # Joins jellyfin watch data (aggregated across all users) with radarr,
  # sonarr and seerr state, ranks every title that is fair game by its most
  # recent sign of life and emits the full ranking plus the bottom
  # $removePercent of it as removal candidates, least active first.
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

    def day: todate | .[0:10];

    # Titles that stay out of the ranking altogether, so they neither get
    # evicted nor count towards the share that does.
    def protection($now; $minAge):
      if .favorite then "favorite"
      elif .arr == null then "unmanaged"
      elif .added == null then "undated"
      elif ($now - .added) < ($minAge * 86400) then "added recently"
      else null end;

    def entry($now):
      {
        type: .type,
        title: .title,
        arrId: .arr.id,
        size: .arr.size,
        seerrIds: .seerrIds,
        idleDays: ((($now - .lastActivity) / 86400) | floor),
        reason: (if .lastPlayed == null then "never watched, added \(.added | day)"
                 elif .lastPlayed >= .added then "last watched \(.lastPlayed | day)"
                 else "last watched \(.lastPlayed | day), \(if .type == "series" then "new episodes" else "added" end) \(.added | day)" end)
      };

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
    # One row per user per item comes in; fold to one per item. A play by
    # anyone counts for everyone, any favorite mark by anyone protects it.
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
    # DateCreated lifts shows with a freshly added season, and the newest
    # LastPlayedDate across all users and seasons is what "actively watching"
    # means.
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
    # A title's standing is its most recent sign of life: the last play by
    # anyone, or the last time something landed on disk for it (the request
    # being fulfilled, an upgrade, a new season), whichever is newer.
    | map(. + { lastActivity: ([ .lastPlayed, .added ] | max) })
    | map(. + { protectedBy: protection($now; $minAgeDays) }) as $all
    # Most recently active first, so the tail of the list is what goes.
    | ($all
        | map(select(.protectedBy == null))
        | sort_by(.lastActivity)
        | reverse
      ) as $ranked
    | ($ranked | length) as $n
    | (($n * $removePercent / 100) | floor) as $cut
    | [ $ranked
        | to_entries[]
        | { rank: (.key + 1), remove: (.key >= ($n - $cut)) } + (.value | entry($now))
      ] as $ranking
    | ($ranking | map(select(.remove)) | reverse) as $chosen
    | {
        generated: ($now | todate),
        policy: {
          removePercent: $removePercent,
          minAgeDays: $minAgeDays
        },
        summary: {
          titles: ($all | length),
          ranked: $n,
          removing: ($chosen | length),
          protected: ($all
            | map(select(.protectedBy != null))
            | group_by(.protectedBy)
            | map({ key: .[0].protectedBy, value: length })
            | from_entries)
        },
        totalSize: ($chosen | map(.size // 0) | add // 0),
        ranking: $ranking,
        protected: ($all
          | map(select(.protectedBy != null) | { type, title, protectedBy })
          | sort_by(.protectedBy, (.title // "" | ascii_downcase))),
        candidates: $chosen
      }
  '';

  # Renders the report as a table for --ranking.
  rankingScript = pkgs.writeText "media-janitor-ranking.jq" ''
    def pad($w): tostring | . + ([ range(length; $w) ] | map(" ") | join(""));
    def lpad($w): tostring | ([ range(length; $w) ] | map(" ") | join("")) + .;
    def gib: ((. // 0) / 1073741824 * 10 | round) / 10 | "\(.) GiB";

    (.ranking | length | tostring | length) as $rw
    | "\(.summary.ranked) titles ranked, the bottom \(.policy.removePercent)% (\(.summary.removing) titles, \(.totalSize | gib)) is marked with -",
      (.summary.protected | to_entries[] | "\(.value) left out: \(.key)"),
      "",
      (.ranking[]
        | "\(if .remove then "-" else " " end) \(.rank | lpad($rw))  \("\(.idleDays)d" | lpad(5))  \(.type | pad(6))  \(.size | gib | lpad(10))  \(.title) (\(.reason))")
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
    | ($r | map("**\(.title)**\(if .type == "series" then " (series)" else "" end) — \(.size | human), \(.reason)")) as $all
    # A tenth of a big library does not fit an embed, so stop at whole
    # lines before discord's 4096 character limit and count the rest.
    | (reduce $all[] as $l ({ text: "", n: 0, full: false };
        if .full or ((.text | length) + ($l | length) + 1) > 3900 then .full = true
        else (.text += ((if .text == "" then "" else "\n" end) + $l)) | (.n += 1) end)
      ) as $acc
    | ($acc.text
        + (if $acc.n < ($all | length) then "\n… and \(($all | length) - $acc.n) more" else "" end)
      ) as $lines
    | ([ "bottom \(.percent)% of \(.ranked) ranked titles",
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
              footer: { text: $foot }
            }
            + (if $lines == "" then {} else { description: $lines } end)
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
      remove_percent=${toString cfg.removePercent}

      delete=false
      as_json=false
      as_ranking=false
      webhook=true

      usage() { cat ${helpText}; }
      die() { echo "media-janitor: $*" >&2; exit 1; }

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --delete) delete=true ;;
          --dry-run) delete=false ;;
          --json) as_json=true ;;
          --ranking) as_ranking=true ;;
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

      # Jellyfin 10.11 removed the legacy X-Emby-Token header; the
      # MediaBrowser scheme works on both old and new versions.
      jf_auth="Authorization: MediaBrowser Token=\"$jellyfin_key\", Client=\"media-janitor\""
      jf_get() { curl "''${curl_opts[@]}" --header "$jf_auth" "$1"; }
      jf_post() { curl "''${curl_opts[@]}" --request POST --header "$jf_auth" "$1"; }
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
        --argjson removePercent "$remove_percent" \
        -f ${policyScript})"

      if [ "$as_json" = true ]; then
        jq '.' <<< "$report"
        exit 0
      fi

      if [ "$as_ranking" = true ]; then
        jq -r -f ${rankingScript} <<< "$report"
        exit 0
      fi

      count="$(jq '.candidates | length' <<< "$report")"
      if [ "$count" -eq 0 ]; then
        echo "media-janitor: nothing to remove"
        jq -r '"  \(.summary.ranked) titles ranked, the bottom \(.policy.removePercent)% of that rounds down to none",
               (.summary.protected | to_entries[] | "  \(.value) left out: \(.key)")' <<< "$report"
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
        jq -r '"media-janitor: dry run, would remove the bottom \(.policy.removePercent)% (\(.summary.removing) of \(.summary.ranked) ranked titles):",
               (.candidates[] | "  #\(.rank) \(.title) [\(.type)] — \(((.size // 0) / 1073741824 * 10 | round) / 10) GiB, \(.reason)")' <<< "$report"
      fi

      jq -s '.' "$tmp/removed.jsonl" > "$tmp/removed.json"
      jq -R -s 'split("\n") | map(select(. != ""))' "$tmp/failed.txt" > "$tmp/failed.json"

      # -- report ------------------------------------------------------------

      if [ "$delete" = true ]; then dry_json=false; else dry_json=true; fi
      outcome="$(jq -n \
        --argjson dryRun "$dry_json" \
        --argjson ranked "$(jq '.summary.ranked' <<< "$report")" \
        --argjson percent "$remove_percent" \
        --slurpfile removed "$tmp/removed.json" \
        --slurpfile failed "$tmp/failed.json" \
        '{ dryRun: $dryRun, ranked: $ranked, percent: $percent,
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
      type = lib.types.ints.unsigned;
      default = 60;
      description = ''
        Grace period: anything added to the library within this many days is
        left out of the ranking, so it is never touched and does not count
        towards removePercent. For series the clock restarts whenever a new
        episode lands. 0 ranks everything that is not a favorite.
      '';
    };

    removePercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 10;
      description = ''
        Share of the ranking evicted per run, rounded down. Every movie and
        series that is not a favorite, unmanaged by radarr/sonarr or inside
        the minAgeDays grace period is ranked by its most recent sign of
        life, the last play by anyone (partial ones included) or the last
        time something landed on disk for it, whichever is newer, and this
        many percent from the bottom go. Being a share of the library, it
        also bounds how much a bad API answer can take out in one run.
      '';
    };

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        While true the timer only reports what it would remove, both to the
        journal and to discord. Set to false once the ranking looks sane.
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
      description = "evict the least watched media and its arr/seerr tracking";
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
