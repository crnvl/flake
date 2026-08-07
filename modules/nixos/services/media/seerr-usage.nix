{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.seerrUsage;

  helpText = pkgs.writeText "seerr-usage-help.txt" ''
    seerr-usage - on-disk size of the jellyfin content each seerr user requested

    usage: seerr-usage [options]

      -d, --details     list every title underneath its requester
          --user NAME   only show users matching NAME (substring, ignoring case)
          --top N       only show the N heaviest users
          --json        print the raw report as JSON instead of a table
      -h, --help        this text

    Sizes are read back from radarr and sonarr, so only content that actually
    landed on disk is counted; series are accounted per requested season. When
    several people asked for the same thing the bytes are billed to whoever
    asked first, so the column still adds up to what the library really holds.

    Needs to run as root: the seerr api key lives in its state directory and the
    radarr/sonarr keys are agenix secrets.
  '';

  # Folds the seerr request list together with radarr/sonarr size data into a
  # per-user report. A movie is one unit, a series request is one unit per
  # requested season, and units are deduplicated on (service id, season) with
  # the earliest request winning, so shared titles are not counted twice.
  collectScript = pkgs.writeText "seerr-usage-collect.jq" ''
    def who:
      [ .displayName, .username, .jellyfinUsername, .plexUsername, .email ]
      | map(select(type == "string" and . != ""))
      | first // "unknown";

    ($rawRequests[0] // []) as $requests
    | ($rawMovies[0] // []) as $movies
    | ($rawSeries[0] // []) as $seriesList
    | ($rawFiles[0] // {}) as $episodeFiles
    | ( $movies
        | map({ key: (.id | tostring), value: { title: (.title // "?"), size: (.sizeOnDisk // 0) } })
        | from_entries
      ) as $movieById
    | ( $seriesList
        | map({ key: (.id | tostring), value: (.title // "?") })
        | from_entries
      ) as $seriesById
    | [ $requests[]
        | . as $req
        | (.media // {}) as $m
        | (.is4k // false) as $k
        | (if $k then $m.externalServiceId4k else $m.externalServiceId end) as $raw
        | (if $raw == null then null else ($raw | tostring) end) as $sid
        | "tmdb\($m.tmdbId // "?")" as $fallback
        | "tmdb \($m.tmdbId // "?")" as $unnamed
        | ((.requestedBy // {}) | who) as $user
        | (.type // $m.mediaType // "unknown") as $type
        | ( if $type == "movie" then
              (if $sid == null then null else $movieById[$sid] end) as $mv
              | [ { dedupe: "movie:\($k):\($sid // $fallback)",
                    group: "movie:\($sid // $fallback)",
                    title: (if $mv == null then $unnamed else $mv.title end),
                    size: (if $mv == null then 0 else $mv.size end) } ]
            else
              (if $sid == null then [] else ($episodeFiles[$sid] // []) end) as $files
              | ([ (.seasons // [])[] | .seasonNumber ] | unique) as $asked
              | (if ($asked | length) > 0 then $asked else ($files | map(.seasonNumber) | unique) end) as $seasons
              | [ $seasons[]
                  | . as $n
                  | { dedupe: "tv:\($k):\($sid // $fallback):\($n)",
                      group: "tv:\($sid // $fallback)",
                      title: (if $sid == null then $unnamed else ($seriesById[$sid] // "sonarr #\($sid)") end),
                      size: ($files | map(select(.seasonNumber == $n) | .size) | add // 0) } ]
            end )
        | .[]
        | . + { user: $user, type: $type, is4k: $k, request: $req.id, requested: ($req.createdAt // "") }
      ] as $all
    | ($all | group_by(.dedupe) | map(sort_by(.requested) | .[0])) as $units
    | ($units | map(.size) | add // 0) as $total
    | {
        generated: (now | todate),
        totals: {
          size: $total,
          claimed: ($all | map(.size) | add // 0),
          requests: ($all | map(.request) | unique | length),
          units: ($units | length),
          movies: ($units | map(select(.type == "movie")) | length),
          seasons: ($units | map(select(.type != "movie")) | length),
          missing: ($units | map(select(.size <= 0)) | length),
          users: ($units | map(.user) | unique | length)
        },
        users: (
          $units
          | group_by(.user)
          | map(
              (map(.size) | add // 0) as $mine
              | {
                  user: .[0].user,
                  size: $mine,
                  share: (if $total > 0 then (($mine / $total) * 1000 | round) / 10 else 0 end),
                  requests: (map(.request) | unique | length),
                  movies: (map(select(.type == "movie")) | length),
                  seasons: (map(select(.type != "movie")) | length),
                  missing: (map(select(.size <= 0)) | length),
                  items: (
                    group_by(.group)
                    | map({
                        title: .[0].title,
                        type: .[0].type,
                        parts: length,
                        size: (map(.size) | add // 0)
                      })
                    | sort_by(-.size)
                  )
                }
            )
          | sort_by(-.size)
        )
      }
  '';

  renderScript = pkgs.writeText "seerr-usage-render.jq" ''
    def spaces($n): if $n <= 0 then "" else (" " * $n) end;
    def rule($n): if $n <= 0 then "" else ("-" * $n) end;
    def pad($n): tostring | . + spaces($n - length);
    def lpad($n): tostring | spaces($n - length) + .;

    def human:
      (. // 0) as $b
      | if $b < 1024 then "\($b | floor) B"
        else
          ([ range(1; 7) ] | map(select(pow(1024; .) <= $b)) | last) as $i
          | ((($b / pow(1024; $i)) * 10 | round) / 10) as $v
          | "\($v) \([ "B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB" ][$i])"
        end;

    . as $report
    | ($report.users | (if $top > 0 then .[0:$top] else . end)) as $rows
    | ([ ($rows[].user | length), 5 ] | max) as $w
    | ($rows | map(.size) | add // 0) as $shown
    | (if $report.totals.size > 0 then $report.totals.size else 1 end) as $denom
    | [ "seerr requests by user",
        "",
        ( ("USER" | pad($w)) + "  " + ("SIZE" | lpad(10)) + "  " + ("SHARE" | lpad(6))
          + "  " + ("MOVIES" | lpad(6)) + "  " + ("SEASONS" | lpad(7)) + "  " + ("MISSING" | lpad(7)) ),
        rule($w + 46)
      ]
      + ( $rows
          | map(
              [ ( (.user | pad($w)) + "  " + (.size | human | lpad(10)) + "  " + ("\(.share)%" | lpad(6))
                  + "  " + (.movies | lpad(6)) + "  " + (.seasons | lpad(7)) + "  " + (.missing | lpad(7)) ) ]
              + ( if $details then
                    ( .items
                      | map("    " + (.size | human | lpad(10)) + "  " + .title
                            + (if .parts > 1 then " (\(.parts) seasons)" else "" end)) )
                    + [ "" ]
                  else [] end )
            )
          | add // [] )
      + [ rule($w + 46),
          ( ("TOTAL" | pad($w)) + "  " + ($shown | human | lpad(10))
            + "  " + ("\((($shown / $denom) * 1000 | round) / 10)%" | lpad(6))
            + "  " + (($rows | map(.movies) | add // 0) | lpad(6))
            + "  " + (($rows | map(.seasons) | add // 0) | lpad(7))
            + "  " + (($rows | map(.missing) | add // 0) | lpad(7)) ),
          "",
          "\($report.totals.requests) requests, \($report.totals.units) deduplicated items, \($report.totals.missing) of them not on disk.",
          "\(($report.totals.claimed - $report.totals.size) | human) was requested more than once and is billed to whoever asked first."
        ]
    | .[]
  '';

  usageScript = pkgs.writeShellApplication {
    name = "seerr-usage";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
    ];
    text = ''
      seerr_url=${lib.escapeShellArg cfg.seerrUrl}
      radarr_url=${lib.escapeShellArg cfg.radarrUrl}
      sonarr_url=${lib.escapeShellArg cfg.sonarrUrl}
      settings=${lib.escapeShellArg (toString cfg.settingsFile)}
      radarr_key_file=${lib.escapeShellArg (toString cfg.radarrKeyFile)}
      sonarr_key_file=${lib.escapeShellArg (toString cfg.sonarrKeyFile)}

      details=false
      as_json=false
      only_user=""
      top=0

      usage() { cat ${helpText}; }

      while [ "$#" -gt 0 ]; do
        case "$1" in
          -d|--details) details=true ;;
          --json) as_json=true ;;
          --user)
            [ "$#" -ge 2 ] || { echo "seerr-usage: --user wants a value" >&2; exit 2; }
            shift
            only_user="$1"
            ;;
          --top)
            [ "$#" -ge 2 ] || { echo "seerr-usage: --top wants a value" >&2; exit 2; }
            shift
            case "$1" in
              "" | *[!0-9]*) echo "seerr-usage: --top wants a number, got $1" >&2; exit 2 ;;
            esac
            top="$1"
            ;;
          -h|--help) usage; exit 0 ;;
          *) echo "seerr-usage: unknown argument $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
      done

      if [ ! -r "$settings" ]; then
        echo "seerr-usage: cannot read $settings, run this as root" >&2
        exit 1
      fi

      seerr_key="$(jq -r '.main.apiKey // empty' "$settings")"
      if [ -z "$seerr_key" ]; then
        echo "seerr-usage: no main.apiKey in $settings" >&2
        exit 1
      fi

      read_key() {
        if [ ! -r "$1" ]; then
          echo "seerr-usage: cannot read the $2 api key at $1, run this as root" >&2
          return 1
        fi
        tr -d '[:space:]' < "$1"
      }

      radarr_key="$(read_key "$radarr_key_file" radarr)"
      sonarr_key="$(read_key "$sonarr_key_file" sonarr)"

      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      get() {
        curl --fail --silent --show-error --location --max-time 120 \
          --retry 2 --retry-delay 2 --retry-all-errors \
          --header "X-Api-Key: $2" "$1"
      }

      # The request list is paginated and there is no "give me everything"
      # switch, so walk it until a short page comes back.
      : > "$tmp/requests.jsonl"
      skip=0
      take=100
      while : ; do
        if ! page="$(get "$seerr_url/api/v1/request?take=$take&skip=$skip&filter=all&sort=added" "$seerr_key")"; then
          echo "seerr-usage: no answer from seerr at $seerr_url" >&2
          exit 1
        fi
        count="$(jq '.results | length' <<< "$page")"
        jq -c '.results[]' <<< "$page" >> "$tmp/requests.jsonl"
        if [ "$count" -lt "$take" ]; then
          break
        fi
        skip=$(( skip + take ))
      done
      jq -s '.' "$tmp/requests.jsonl" > "$tmp/requests.json"

      if movies="$(get "$radarr_url/api/v3/movie" "$radarr_key")"; then
        printf '%s' "$movies" > "$tmp/movies.json"
      else
        echo "seerr-usage: radarr unreachable at $radarr_url, movies will show as 0 bytes" >&2
        echo '[]' > "$tmp/movies.json"
      fi

      if series="$(get "$sonarr_url/api/v3/series" "$sonarr_key")"; then
        printf '%s' "$series" > "$tmp/series.json"
      else
        echo "seerr-usage: sonarr unreachable at $sonarr_url, series will show as 0 bytes" >&2
        echo '[]' > "$tmp/series.json"
      fi

      # Per-season sizes need the episode file list, and sonarr only hands that
      # out one series at a time, so ask for the ones that were requested.
      jq -r '
        [ .[]
          | select(((.type // .media.mediaType) // "") == "tv")
          | (if (.is4k // false) then .media.externalServiceId4k else .media.externalServiceId end)
          | select(. != null)
        ] | unique | .[]
      ' "$tmp/requests.json" > "$tmp/series-ids"

      : > "$tmp/files.jsonl"
      while read -r sid; do
        if [ -z "$sid" ]; then
          continue
        fi
        if files="$(get "$sonarr_url/api/v3/episodefile?seriesId=$sid" "$sonarr_key")"; then
          jq -c --arg id "$sid" \
            '{ key: $id, value: [ .[] | { seasonNumber: (.seasonNumber // 0), size: (.size // 0) } ] }' \
            <<< "$files" >> "$tmp/files.jsonl"
        else
          echo "seerr-usage: sonarr has no episode files for series $sid" >&2
        fi
      done < "$tmp/series-ids"
      jq -s 'from_entries' "$tmp/files.jsonl" > "$tmp/files.json"

      report="$(jq -n \
        --slurpfile rawRequests "$tmp/requests.json" \
        --slurpfile rawMovies "$tmp/movies.json" \
        --slurpfile rawSeries "$tmp/series.json" \
        --slurpfile rawFiles "$tmp/files.json" \
        -f ${collectScript})"

      if [ -n "$only_user" ]; then
        report="$(jq --arg u "$only_user" \
          '.users |= map(select(.user | ascii_downcase | contains($u | ascii_downcase)))' \
          <<< "$report")"
      fi

      if [ "$as_json" = true ]; then
        jq '.' <<< "$report"
      else
        jq -r --argjson details "$details" --argjson top "$top" -f ${renderScript} <<< "$report"
      fi
    '';
  };
in
{
  options.my.seerrUsage = {
    seerrUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:${toString config.services.seerr.port}";
      defaultText = lib.literalExpression ''"http://localhost:''${toString config.services.seerr.port}"'';
      description = "Base URL of the seerr instance to read requests from.";
    };

    radarrUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:7878";
      description = "Base URL of radarr, used for movie sizes on disk.";
    };

    sonarrUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8989";
      description = "Base URL of sonarr, used for per-season sizes on disk.";
    };

    settingsFile = lib.mkOption {
      type = lib.types.path;
      default = "${lib.removeSuffix "/" (toString config.services.seerr.configDir)}/settings.json";
      defaultText = lib.literalExpression ''"''${config.services.seerr.configDir}/settings.json"'';
      description = ''
        Seerr's settings file, which is where its API key lives. Only root can
        read it, since the service runs under a DynamicUser.
      '';
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
  };

  config = {
    age.secrets = {
      radarr-api-key.file = ../../../../hosts/shimmers/secrets/radarr-api-key.age;
      sonarr-api-key.file = ../../../../hosts/shimmers/secrets/sonarr-api-key.age;
    };

    environment.systemPackages = [ usageScript ];
  };
}
