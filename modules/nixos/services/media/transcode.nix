{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.mediaTranscode;

  helpText = pkgs.writeText "media-transcode-help.txt" ''
    media-transcode - re-encode large H.264 files to HEVC to save space

    usage: media-transcode <command>

      --list      print the files still to do, biggest bitrate first
      --status    print what has been done so far and what is left
      --run         work through the list (what the service runs)
      --file PATH   do just this one file from the list, e.g. to try it out
                    (sudo systemctl start media-transcode-file@$(systemd-escape --path PATH))
      -h, --help    this text

    Picks H.264 movies and episodes from radarr and sonarr that average at
    least ${toString cfg.minMbps} Mbit/s and were imported more than ${toString cfg.minAgeDays} days ago, and
    re-encodes their video to 10-bit HEVC (x265 ${cfg.preset}, CRF ${toString cfg.crf}). Audio,
    subtitles, fonts and chapters are copied as they are. The result only
    replaces the original if it has the same length and streams and is at
    most ${toString cfg.maxSizePercent}% of its size; either way the file is not tried again until
    radarr or sonarr replace it. The file keeps its name, radarr or sonarr
    rescan it and jellyfin is told to probe it again.

    --list and --status need root for the API keys.
  '';

  # Movie files from radarr and episode files from sonarr, as one list.
  # $handled holds earlier results by path; a file whose size is either the
  # one it had before or after is one we already dealt with.
  candidatesScript = pkgs.writeText "media-transcode-candidates.jq" ''
    def secs: split(":") | map(tonumber? // 0) | reduce .[] as $x (0; . * 60 + $x);
    def ts: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;

    ($handled | map({ key: .path, value: [ .before, .after ] }) | from_entries) as $seen
    | now as $now
    | [ .[]
        | select(.mediaInfo.videoCodec != null
                 and (.mediaInfo.videoCodec | ascii_downcase | IN("x264", "h264", "avc")))
        | select(.path | test("\\.(mkv|mp4|m4v)$"; "i"))
        # Would keep the combing, and is too rare to be worth deinterlacing.
        | select((.mediaInfo.scanType // "") != "Interlaced")
        | . + { secs: (.mediaInfo.runTime // "0" | secs) }
        | select(.secs > 0)
        | . + { mbps: (.size * 8 / .secs / 1000000) }
        | select(.mbps >= $minMbps)
        | select(($now - (.dateAdded | ts)) > $minAgeDays * 86400)
        | select(.path as $p | .size | IN(($seen[$p] // [])[]) | not)
        | { app, id, path, size, secs, mbps }
      ]
    | sort_by(-.mbps)
  '';

  transcodeScript = pkgs.writeShellApplication {
    name = "media-transcode";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      ffmpeg-headless
      gawk
      jq
    ];
    text = ''
      radarr_url=${lib.escapeShellArg cfg.radarrUrl}
      sonarr_url=${lib.escapeShellArg cfg.sonarrUrl}
      jellyfin_url=${lib.escapeShellArg cfg.jellyfinUrl}
      min_mbps=${toString cfg.minMbps}
      min_age=${toString cfg.minAgeDays}
      max_percent=${toString cfg.maxSizePercent}
      state="''${STATE_DIRECTORY:-/var/lib/media-transcode}"
      results="$state/results.jsonl"
      work="$state/work"

      log() { echo "media-transcode: $*" >&2; }
      die() { log "$*"; exit 1; }

      # The service gets the keys as credentials, a root shell reads them
      # straight from agenix.
      read_key() { # <credential name> <agenix path>
        local file="$2"
        if [ -n "''${CREDENTIALS_DIRECTORY:-}" ]; then
          file="$CREDENTIALS_DIRECTORY/$1"
        fi
        [ -r "$file" ] || die "cannot read the $1 key at $file, run this as root"
        tr -d '[:space:]' < "$file"
      }

      curl_opts=(
        --fail --silent --show-error --max-time 120
        --retry 3 --retry-delay 5 --retry-all-errors
      )

      gib() { awk -v b="$1" 'BEGIN { printf "%.1f GiB", b / 1073741824 }'; }

      candidates() {
        local radarr_key sonarr_key series done_json
        radarr_key="$(read_key radarr ${lib.escapeShellArg config.age.secrets.radarr-api-key.path})"
        sonarr_key="$(read_key sonarr ${lib.escapeShellArg config.age.secrets.sonarr-api-key.path})"
        done_json="[]"
        if [ -s "$results" ]; then
          done_json="$(jq -s '.' "$results")"
        fi
        {
          curl "''${curl_opts[@]}" --header "X-Api-Key: $radarr_key" "$radarr_url/api/v3/movie" \
            | jq -c '.[] | .movieFile | select(.) | . + { app: "radarr", id: .movieId }'
          series="$(curl "''${curl_opts[@]}" --header "X-Api-Key: $sonarr_key" "$sonarr_url/api/v3/series")"
          for id in $(jq -r '.[] | select((.statistics.episodeFileCount // 0) > 0) | .id' <<< "$series"); do
            curl "''${curl_opts[@]}" --header "X-Api-Key: $sonarr_key" "$sonarr_url/api/v3/episodefile?seriesId=$id" \
              | jq -c '.[] | . + { app: "sonarr", id: .seriesId }'
          done
        } | jq -s \
          --argjson handled "$done_json" \
          --argjson minMbps "$min_mbps" \
          --argjson minAgeDays "$min_age" \
          -f ${candidatesScript}
      }

      list() {
        candidates | jq -r '
          def gib: (. / 1073741824 * 10 | round) / 10 | "\(.) GiB";
          "\(length) files, \(map(.size) | add // 0 | gib), \(map(.secs) | add // 0 | . / 3600 | round) h of video",
          (.[] | "\(.mbps * 10 | round / 10 | tostring | . + " Mbit/s" | .[0:12])  \(.size | gib)  \(.path)")'
      }

      status() {
        if [ -s "$results" ]; then
          jq -rs '
            def gib: (. / 1073741824 * 10 | round) / 10 | "\(.) GiB";
            map(select(.result == "done")) as $d
            | "done: \($d | length) files, \($d | map(.before) | add // 0 | gib) -> \($d | map(.after) | add // 0 | gib), saved \($d | map(.before - .after) | add // 0 | gib)",
              (if ($d | length) > 0 then "speed: \($d | map(.secs) | add) / \($d | map(.took) | add) = \(($d | map(.secs) | add) / ($d | map(.took) | add) * 10 | round / 10)x real time" else empty end),
              (group_by(.result) | map(select(.[0].result != "done") | "\(.[0].result): \(length) files") | .[]),
              "last: \(last | "\(.at) \(.result) \(.path)")"' "$results"
        else
          echo "nothing done yet"
        fi
        candidates | jq -r '
          def gib: (. / 1073741824 * 10 | round) / 10 | "\(.) GiB";
          "left: \(length) files, \(map(.size) | add // 0 | gib), \(map(.secs) | add // 0 | . / 3600 | round) h of video"'
      }

      record() { # <candidate json> <result> <after bytes or null> <took seconds> [note]
        jq -nc --argjson c "$1" --arg result "$2" --argjson after "$3" --argjson took "$4" --arg note "''${5:-}" \
          '{ at: (now | todate), path: $c.path, result: $result, before: $c.size, after: $after,
             secs: $c.secs, took: $took } + (if $note == "" then {} else { note: $note } end)' >> "$results"
      }

      probe_duration() {
        ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"
      }

      probe_streams() { # counts of audio, subtitle and attachment streams
        ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$1" \
          | awk '/^(audio|subtitle|attachment)/ { n[$1]++ } END { printf "a%d s%d t%d", n["audio"], n["subtitle"], n["attachment"] }'
      }

      # Tells the arr to rescan and jellyfin to probe the file again, so
      # neither keeps offering it as H.264.
      announce() { # <candidate json>
        local app id path key url body
        app="$(jq -r .app <<< "$1")"
        id="$(jq -r .id <<< "$1")"
        path="$(jq -r .path <<< "$1")"
        if [ "$app" = radarr ]; then
          key="$(read_key radarr ${lib.escapeShellArg config.age.secrets.radarr-api-key.path})"
          url="$radarr_url/api/v3/command"
          body="$(jq -nc --argjson id "$id" '{ name: "RescanMovie", movieId: $id }')"
        else
          key="$(read_key sonarr ${lib.escapeShellArg config.age.secrets.sonarr-api-key.path})"
          url="$sonarr_url/api/v3/command"
          body="$(jq -nc --argjson id "$id" '{ name: "RescanSeries", seriesId: $id }')"
        fi
        curl "''${curl_opts[@]}" --request POST --header "X-Api-Key: $key" \
          --header "Content-Type: application/json" --data-binary "$body" "$url" > /dev/null \
          || log "could not ask $app to rescan $path"

        key="$(read_key jellyfin ${lib.escapeShellArg config.age.secrets.jellyfin-api-key.path})"
        curl "''${curl_opts[@]}" --request POST \
          --header "Authorization: MediaBrowser Token=\"$key\", Client=\"media-transcode\"" \
          --header "Content-Type: application/json" \
          --data-binary "$(jq -nc --arg p "$path" '{ Updates: [ { Path: $p, UpdateType: "Modified" } ] }')" \
          "$jellyfin_url/Library/Media/Updated" > /dev/null \
          || log "could not tell jellyfin about $path"
      }

      cifs_tmp=""
      cleanup() {
        rm -rf "''${work:?}"/*
        if [ -n "$cifs_tmp" ]; then
          rm -f "$cifs_tmp"
        fi
      }

      transcode() { # <candidate json>
        local c="$1" src ext out size mtime start took in_dur out_dur in_streams out_streams after
        local args
        src="$(jq -r .path <<< "$c")"
        size="$(jq -r .size <<< "$c")"
        ext="''${src##*.}"
        ext="''${ext,,}"
        out="$work/out.$ext"

        # Gone or replaced since the list was made: leave it for next time.
        if [ ! -f "$src" ] || [ "$(stat -c %s "$src")" != "$size" ]; then
          log "skipping $src, it changed since the list was made"
          return 0
        fi
        mtime="$(stat -c %Y "$src")"

        args=(-hide_banner -loglevel error -nostdin -y -i "$src" -map 0:v:0 -map "0:a?" -map "0:s?")
        if [ "$ext" = mkv ]; then
          # The muxer's statistics tags describe the old video stream; the
          # copied streams keep theirs, which stay true.
          args+=(-map "0:t?")
          for tag in BPS NUMBER_OF_BYTES NUMBER_OF_FRAMES DURATION _STATISTICS_TAGS \
                     _STATISTICS_WRITING_APP _STATISTICS_WRITING_DATE_UTC; do
            args+=(-metadata:s:v:0 "$tag=")
          done
        else
          # Apple players only take HEVC in mp4 under the hvc1 tag.
          args+=(-tag:v:0 hvc1 -movflags +faststart)
        fi
        args+=(-c copy -c:v:0 libx265 -preset ${lib.escapeShellArg cfg.preset} -crf ${toString cfg.crf}
               -pix_fmt yuv420p10le -x265-params log-level=error -max_muxing_queue_size 4096 "$out")

        start="$(date +%s)"
        if ! ffmpeg "''${args[@]}" 2> "$work/ffmpeg.log"; then
          took=$(( $(date +%s) - start ))
          log "ffmpeg failed on $src: $(tail -c 300 "$work/ffmpeg.log")"
          record "$c" failed null "$took" "$(tail -c 300 "$work/ffmpeg.log")"
          return 0
        fi
        took=$(( $(date +%s) - start ))

        in_dur="$(probe_duration "$src")"
        out_dur="$(probe_duration "$out")"
        if ! awk -v a="$in_dur" -v b="$out_dur" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d <= 2 || d <= a * 0.005) }'; then
          log "length changed on $src ($in_dur s -> $out_dur s), keeping the original"
          record "$c" failed null "$took" "length $in_dur -> $out_dur"
          return 0
        fi
        in_streams="$(probe_streams "$src")"
        out_streams="$(probe_streams "$out")"
        if [ "$ext" != mkv ]; then
          in_streams="''${in_streams% t*}"
          out_streams="''${out_streams% t*}"
        fi
        if [ "$in_streams" != "$out_streams" ]; then
          log "streams changed on $src ($in_streams -> $out_streams), keeping the original"
          record "$c" failed null "$took" "streams $in_streams -> $out_streams"
          return 0
        fi
        after="$(stat -c %s "$out")"
        if [ $(( after * 100 )) -gt $(( size * max_percent )) ]; then
          log "$src only went from $(gib "$size") to $(gib "$after"), keeping the original"
          record "$c" "no gain" "$after" "$took"
          return 0
        fi

        if [ ! -f "$src" ] || [ "$(stat -c %s "$src")" != "$size" ] || [ "$(stat -c %Y "$src")" != "$mtime" ]; then
          log "skipping $src, it changed while it was being encoded"
          return 0
        fi

        # Copied next to the original first, so the swap is one rename on
        # the share. A rename can fail while someone is playing the file.
        cifs_tmp="$(dirname "$src")/.$(basename "$src").transcoded"
        if ! cp "$out" "$cifs_tmp" || [ "$(stat -c %s "$cifs_tmp")" != "$after" ] || ! mv -f "$cifs_tmp" "$src"; then
          log "could not replace $src, trying again next run"
          rm -f "$cifs_tmp"
          cifs_tmp=""
          return 0
        fi
        cifs_tmp=""

        record "$c" "done" "$after" "$took"
        log "$src: $(gib "$size") -> $(gib "$after") ($(( after * 100 / size ))%) in $(( took / 60 )) min"
        announce "$c"
      }

      run() { # [path]
        local queue n=0 total
        mkdir -p "$work"
        trap cleanup EXIT
        cleanup
        queue="$work/../queue.jsonl"
        candidates | jq -c --arg only "''${1:-}" '.[] | select($only == "" or .path == $only)' > "$queue"
        total="$(wc -l < "$queue")"
        if [ -n "''${1:-}" ] && [ "$total" -eq 0 ]; then
          die "$1 is not on the list, see --list"
        fi
        log "$total files to do"
        while IFS= read -r c <&3; do
          n=$(( n + 1 ))
          log "[$n/$total] $(jq -r '"\(.path) (\(.mbps * 10 | round / 10) Mbit/s, \(.size / 1073741824 * 10 | round / 10) GiB)"' <<< "$c")"
          transcode "$c"
          rm -f "$work"/*
        done 3< "$queue"
        rm -f "$queue"
      }

      case "''${1:-}" in
        --list) list ;;
        --status) status ;;
        --run) run ;;
        --file)
          [ "$#" -ge 2 ] || die "--file wants a path"
          run "$2"
          ;;
        -h|--help) cat ${helpText} ;;
        *) cat ${helpText} >&2; exit 2 ;;
      esac
    '';
  };

  wgNamespace = config.vpnNamespaces.wg;

  serviceConfig = {
    Type = "oneshot";
    TimeoutStartSec = "infinity";

    # The same dynamic user for both units, so they share the state.
    DynamicUser = true;
    User = "media-transcode";
    # Write access to the library, which is 0664/0775 jellyfin:media.
    SupplementaryGroups = [ "media" ];
    ReadWritePaths = [ "/mnt/chroma/media" ];
    StateDirectory = "media-transcode";
    LoadCredential = [
      "radarr:${config.age.secrets.radarr-api-key.path}"
      "sonarr:${config.age.secrets.sonarr-api-key.path}"
      "jellyfin:${config.age.secrets.jellyfin-api-key.path}"
    ];

    # Only spare CPU and disk time: jellyfin's own transcoding (there is
    # no GPU) and everything else go first.
    Nice = 19;
    CPUSchedulingPolicy = "idle";
    IOSchedulingClass = "idle";
  };

  unitDeps = {
    after = [
      "network-online.target"
      "radarr.service"
      "sonarr.service"
      "jellyfin.service"
    ];
    wants = [ "network-online.target" ];
    # A run takes weeks; a deploy should not throw away the file in
    # progress. The next start picks up the new settings.
    restartIfChanged = false;
  };
in
{
  options.my.mediaTranscode = {
    radarrUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${wgNamespace.namespaceAddress}:7878";
      defaultText = lib.literalExpression ''"http://''${config.vpnNamespaces.wg.namespaceAddress}:7878"'';
      description = "Base URL of radarr, reached at its vpn namespace address.";
    };

    sonarrUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${wgNamespace.namespaceAddress}:8989";
      defaultText = lib.literalExpression ''"http://''${config.vpnNamespaces.wg.namespaceAddress}:8989"'';
      description = "Base URL of sonarr, reached at its vpn namespace address.";
    };

    jellyfinUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8096";
      description = "Base URL of jellyfin, which gets told about replaced files.";
    };

    minMbps = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = ''
        Only files averaging at least this many Mbit/s (whole file, audio
        included) are worth it. Lower than that, x265 at a CRF that keeps
        the quality often ends up no smaller.
      '';
    };

    minAgeDays = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 30;
      description = ''
        Leave files alone for this many days after import: they are the
        likeliest to still get a quality upgrade or be evicted again.
      '';
    };

    maxSizePercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 80;
      description = "Keep the original unless the new file is at most this share of its size.";
    };

    crf = lib.mkOption {
      type = lib.types.ints.between 0 51;
      # VMAF ~95 on 1080p tests, at 15-30% of the H.264 video's size.
      default = 22;
      description = "x265 constant rate factor; lower is better quality and bigger.";
    };

    preset = lib.mkOption {
      type = lib.types.str;
      default = "medium";
      description = "x265 preset. medium ran at about 2x real time on 1080p here.";
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = ''
        When to (re)start working through the list, systemd.time(7) syntax.
        A run that is still busy just carries on.
      '';
    };
  };

  config = {
    environment.systemPackages = [ transcodeScript ];

    systemd.services.media-transcode = unitDeps // {
      description = "re-encode large H.264 files to HEVC to save space";
      startAt = cfg.onCalendar;
      unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];
      serviceConfig = serviceConfig // {
        ExecStart = "${lib.getExe transcodeScript} --run";
      };
    };

    # One file, e.g. to try the settings out. Both use the same work
    # directory, so this stops a running media-transcode (losing the file
    # in progress); start that again afterwards.
    systemd.services."media-transcode-file@" = unitDeps // {
      description = "re-encode %f to HEVC";
      unitConfig = {
        RequiresMountsFor = [ "/mnt/chroma" ];
        Conflicts = [ "media-transcode.service" ];
      };
      serviceConfig = serviceConfig // {
        ExecStart = "${lib.getExe transcodeScript} --file \"%f\"";
      };
    };
  };
}
