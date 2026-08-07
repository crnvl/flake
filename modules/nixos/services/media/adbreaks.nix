{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.adbreaks;
  norm = cfg.normalize;
  sleepFor = cfg.sleepInterval;

  # dir<TAB>archive<TAB>url per line, fed to the loop below on fd 3 so that
  # yt-dlp and ffmpeg cannot eat the iteration list off stdin. The archive
  # name flattens the group separator, since it is a plain filename.
  playlistTable = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: url: "${name}\t${lib.replaceStrings [ "/" ] [ "_" ] name}\t${url}"
    ) cfg.playlists
  );

  # Keeps hour-long "best of 80s ads" compilations out of a library that is
  # supposed to hold thirty second clips. Applied before the download starts.
  matchFilter = lib.optionalString (cfg.maxDurationSeconds != null) (
    "--match-filter " + lib.escapeShellArg "duration < ${toString cfg.maxDurationSeconds}"
  );

  extractorFlags = lib.concatMapStringsSep "\n          " (
    a: "--extractor-args ${lib.escapeShellArg a}"
  ) cfg.extractorArgs;

  fetchScript = pkgs.writeShellApplication {
    name = "adbreaks-fetch";
    runtimeInputs = with pkgs; [
      coreutils
      yt-dlp
      ffmpeg-headless
      findutils
      gnugrep
      gnused
      jq
    ];
    text = ''
      dir="${cfg.directory}"
      state="''${STATE_DIRECTORY:-/var/lib/adbreaks}"
      normalize_enabled=${lib.boolToString norm.enable}
      budget=${toString cfg.budgetPerRun}
      failures=0
      blocked=0

      loudnorm_base="I=${toString norm.loudness}:TP=${toString norm.truePeak}:LRA=${toString norm.loudnessRange}"

      ${lib.optionalString (cfg.cookieFile != null) ''
        # yt-dlp rewrites the jar as the session refreshes, so it needs a
        # writable copy. Only re-seed when the source is newer, otherwise a
        # refreshed session would be discarded on every single run.
        src_cookies=${lib.escapeShellArg (toString cfg.cookieFile)}
        live_cookies="$state/cookies.txt"
        if [ ! -f "$live_cookies" ] || [ "$src_cookies" -nt "$live_cookies" ]; then
          install -m 0600 "$src_cookies" "$live_cookies"
          echo "seeded cookie jar from $src_cookies"
        fi
      ''}

      # Re-encode to one fixed video and loudness profile, so that clips
      # pulled from thirty different uploads do not change resolution,
      # framerate or volume every time a break starts.
      #
      # Loudness uses the two pass form: measure, then apply one linear gain.
      # The single pass form is a dynamic normalizer and pumps badly on the
      # kind of heavily compressed audio that adverts are mastered with.
      normalize() {
        src="$1"
        dest="$2"
        af="loudnorm=$loudnorm_base"

        if raw="$(ffmpeg -nostdin -hide_banner -i "$src" \
                    -af "loudnorm=$loudnorm_base:print_format=json" \
                    -f null - 2>&1)"; then
          measured="$(printf '%s\n' "$raw" | sed -n '/^{/,/^}/p')"
          if [ -n "$measured" ]; then
            mi="$(jq -r '.input_i // "-inf"' <<<"$measured")"
            mtp="$(jq -r '.input_tp // "-inf"' <<<"$measured")"
            mlra="$(jq -r '.input_lra // "0"' <<<"$measured")"
            mth="$(jq -r '.input_thresh // "-inf"' <<<"$measured")"
            moff="$(jq -r '.target_offset // "0"' <<<"$measured")"

            # A silent or near silent clip measures as -inf and would make
            # the second pass produce garbage, so fall back to one pass.
            case "$mi$mtp$mth" in
              *inf*) ;;
              *)
                af="loudnorm=$loudnorm_base"
                af="$af:measured_I=$mi:measured_TP=$mtp"
                af="$af:measured_LRA=$mlra:measured_thresh=$mth"
                af="$af:offset=$moff:linear=true"
                ;;
            esac
          fi
        fi

        # loudnorm resamples to 192 kHz internally, hence the explicit -ar.
        ffmpeg -nostdin -hide_banner -v error -y -i "$src" \
          -vf "fps=${toString norm.fps},scale=${toString norm.width}:${toString norm.height}:force_original_aspect_ratio=decrease,pad=${toString norm.width}:${toString norm.height}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1" \
          -c:v libx264 -preset veryfast -crf ${toString norm.crf} -pix_fmt yuv420p \
          -af "$af" \
          -c:a aac -b:a 160k -ar 48000 -ac 2 \
          -movflags +faststart \
          "$dest"
      }

      while IFS=$'\t' read -r name archive_name url <&3; do
        [ -n "$name" ] || continue

        if [ "$budget" -le 0 ]; then
          echo "download budget for this run is spent, the rest waits for the next timer"
          break
        fi

        out="$dir/$name"
        work="$dir/.staging/$name"
        archive="$state/$archive_name.archive"
        log="$work/yt-dlp.log"
        rc_file="$work/rc"

        rm -rf "$work"
        mkdir -p "$out" "$work"

        echo "== $name (budget: $budget)"

        # The archive is what makes this incremental and resumable: entries
        # already fetched are skipped straight from the playlist listing,
        # without touching the video page, so a rerun is cheap.
        args=(
          --ignore-config
          --download-archive "$archive"
          --paths "home:$work"
          --paths "temp:$work"
          --output '%(title).100B [%(id)s].%(ext)s'
          --format ${lib.escapeShellArg cfg.format}
          --merge-output-format mp4
          --remux-video mp4
          --embed-metadata
          --no-progress
          --no-overwrites
          --ignore-errors
          --max-downloads "$budget"
          --retries 5
          --extractor-retries 3
          --retry-sleep 'extractor:exp=5:120'
          --retry-sleep 'http:exp=5:120'
          --sleep-requests ${toString cfg.sleepRequests}
          --sleep-interval ${toString sleepFor.min}
          --max-sleep-interval ${toString sleepFor.max}
          ${matchFilter}
          ${extractorFlags}
        )
        ${lib.optionalString (cfg.cookieFile != null) ''
          args+=( --cookies "$live_cookies" )
        ''}

        # errexit off in the subshell, otherwise a yt-dlp failure would kill
        # it before the exit code is recorded.
        ( set +e; yt-dlp "''${args[@]}" -- "$url"; echo "$?" > "$rc_file" ) 2>&1 | tee "$log"
        rc="$(cat "$rc_file")"

        case "$rc" in
          0) ;;
          101) echo "$name: reached the per-run download limit" ;;
          *)
            echo "warning: yt-dlp exited $rc for $name" >&2
            failures=$(( failures + 1 ))
            ;;
        esac

        added=0
        shopt -s nullglob
        for src in "$work"/*; do
          [ -f "$src" ] || continue
          case "$src" in
            "$log" | "$rc_file") continue ;;
          esac
          base="$(basename "$src")"

          if [ "$normalize_enabled" = true ]; then
            dest="$out/''${base%.*}.mp4"
            if normalize "$src" "$dest.part"; then
              mv -f "$dest.part" "$dest"
            else
              # Never lose a clip just because the re-encode choked: the
              # archive already recorded the id, so it is never retried.
              echo "warning: could not normalize $base, storing as-is" >&2
              rm -f "$dest.part"
              mv -f "$src" "$out/$base"
            fi
          else
            mv -f "$src" "$out/$base"
          fi
          added=$(( added + 1 ))
        done
        shopt -u nullglob

        budget=$(( budget - added ))
        echo "$name: $added new, $(find "$out" -type f -name '*.mp4' | wc -l) total"

        # Once YouTube starts refusing, every further request deepens the
        # block. Back off immediately and let the next timer try again.
        refusals="$(grep -c -e 'Sign in to confirm' -e 'HTTP Error 429' "$log" || true)"
        if [ "''${refusals:-0}" -ge ${toString cfg.blockThreshold} ]; then
          echo "youtube refused $refusals times, backing off for this run" >&2
          blocked=1
          break
        fi
      done 3<<'PLAYLISTS'
      ${playlistTable}
      PLAYLISTS

      rm -rf "$dir/.staging"

      echo "library: $(find "$dir" -type f -name '*.mp4' | wc -l) clips, $(du -sh "$dir" | cut -f1)"

      if [ "$blocked" -eq 1 ]; then
        echo "stopped early on rate limiting; the archive resumes from here next run"
        exit 0
      fi

      if [ "$failures" -gt 0 ]; then
        echo "$failures playlist(s) reported errors" >&2
        exit 1
      fi
    '';
  };
in
{
  options.my.adbreaks = {
    directory = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/adbreaks";
      description = ''
        Root for the clip library. Playlists are grouped into subdirectories
        so a whole group can be added to a Tunarr filler list in one go.
      '';
    };

    playlists = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = ''
        Attribute name becomes the subdirectory, and may contain a slash to
        group related playlists. Keep it filesystem friendly.
      '';
      default = {
        "commercials/cars" = "https://www.youtube.com/playlist?list=PLiej1KEFmshrdr5WS185L-bHikEbue8GQ";
        "commercials/food" = "https://www.youtube.com/playlist?list=PLiej1KEFmshpA93uJo0SNiizYz_miCB7D";
        "commercials/music" = "https://www.youtube.com/playlist?list=PLiej1KEFmshrlGFRCKjv6ATkUv0yzdYS3";
        "commercials/stores" = "https://www.youtube.com/playlist?list=PLiej1KEFmshovNOCSiNuzeE0osULlBOtL";
        "commercials/health-beauty" = "https://www.youtube.com/playlist?list=PLiej1KEFmshpml3fsOLWaWBeL7RIpILrM";
        "commercials/household" = "https://www.youtube.com/playlist?list=PLiej1KEFmshp22RsZS9Q4JooM0-6Adra5";
        "commercials/celebrity" = "https://www.youtube.com/playlist?list=PLiej1KEFmshqbdRhVyXU4PNxnxqKVP2bG";
        "commercials/clothing" = "https://www.youtube.com/playlist?list=PLiej1KEFmshpDwSnAlKZfJWdwwfviUbO4";
        "commercials/finance" = "https://www.youtube.com/playlist?list=PLiej1KEFmshrL6u-al1l2_TqAbH0G1W8T";
        "commercials/gaming" = "https://www.youtube.com/playlist?list=PLiej1KEFmshquitTRG1YZ1Wok5inQIH3g";
        "commercials/video-games" = "https://www.youtube.com/playlist?list=PLD3MboLuMLE0OVgQHoqgQhouMJAkNUGdh";
        "commercials/tv" = "https://www.youtube.com/playlist?list=PLJEb1IVKTmCXePGUsLUfl98uhJmDXXMGf";
        "commercials/internet" = "https://www.youtube.com/playlist?list=PLiej1KEFmshqxmK51H5Yhe5qhYHQfTfzm";

        # Intermission reels and channel idents are a different flavour from
        # adverts, so they stay out of the general commercial pool.
        "bumpers/drive-in" = "https://www.youtube.com/playlist?list=PLDNJRIBXF0FOEDWHfkExKHFaztQrof6aE";
        "bumpers/scifi" = "https://www.youtube.com/playlist?list=PLiej1KEFmshr1CgBCAxuD8yzRS65gwHvO";
      };
    };

    budgetPerRun = lib.mkOption {
      type = lib.types.ints.positive;
      default = 50;
      description = ''
        Maximum clips to download across all playlists in one run. This is
        the setting that keeps YouTube from blocking the host: the library
        fills as a trickle over days rather than one long scrape. The
        download archive makes every run resume where the last one stopped.
      '';
    };

    blockThreshold = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = ''
        Abandon the run after this many bot checks or 429s in one playlist.
        Continuing past a refusal only extends the block.
      '';
    };

    format = lib.mkOption {
      type = lib.types.str;
      default = "bv*[height<=1080][vcodec^=avc1]+ba[acodec^=mp4a]/bv*[height<=1080][vcodec^=avc1]+ba/bv*[height<=1080]+ba/b";
      description = ''
        yt-dlp format selector. Prefers H.264 plus AAC so the mp4 remux is a
        stream copy rather than a re-encode.
      '';
    };

    maxDurationSeconds = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 300;
      description = "Skip anything longer than this, or null to accept everything.";
    };

    sleepRequests = lib.mkOption {
      type = lib.types.numbers.nonnegative;
      default = 1.5;
      description = "Seconds to wait between metadata requests.";
    };

    sleepInterval = {
      min = lib.mkOption {
        type = lib.types.numbers.nonnegative;
        default = 5;
        description = "Lower bound of the randomised pause between downloads.";
      };
      max = lib.mkOption {
        type = lib.types.numbers.nonnegative;
        default = 20;
        description = ''
          Upper bound of the randomised pause between downloads. A varying
          gap draws less attention than a metronomic one.
        '';
      };
    };

    extractorArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "youtube:player_client=default,tv_simply" ];
      description = ''
        Passed through as --extractor-args. Useful for steering yt-dlp at
        player clients that are currently less aggressively challenged.
        Deliberately empty by default, because which clients work changes
        often enough that a baked-in value would rot.
      '';
    };

    cookieFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Netscape cookie jar, for when YouTube demands sign-in. Point this at
        an agenix secret; it is copied to a writable location, since yt-dlp
        rewrites the jar as the session refreshes.
      '';
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 00/3:17:00";
      description = ''
        OnCalendar expression, in local time. Runs often and takes a little
        each time, rather than rarely and everything at once.
      '';
    };

    normalize = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Re-encode every clip to one video and loudness profile. Worth the
          CPU for short clips: it removes the resolution and volume jumps
          that otherwise make a break obvious in the worst way.
        '';
      };

      width = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1280;
        description = ''
          Target width, letterboxed to preserve aspect ratio. Most of this
          material is upscaled standard definition, so encoding it at 1080p
          multiplies the file size without recovering any detail.
        '';
      };

      height = lib.mkOption {
        type = lib.types.ints.positive;
        default = 720;
        description = "Target height, letterboxed to preserve aspect ratio.";
      };

      fps = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = ''
          Target framerate. These playlists are almost entirely NTSC sourced,
          so 30 avoids the frame drops of a conversion to 25. Match this to
          the channel's ffmpeg framerate in Tunarr.
        '';
      };

      crf = lib.mkOption {
        type = lib.types.ints.between 0 51;
        default = 21;
        description = "x264 quality; lower is better and larger.";
      };

      loudness = lib.mkOption {
        type = lib.types.int;
        default = -18;
        description = ''
          Integrated loudness target in LUFS. Broadcast is -23, streaming
          sits nearer -16; -18 keeps adverts from being louder than the
          programme they interrupt, which is the whole point.
        '';
      };

      truePeak = lib.mkOption {
        type = lib.types.numbers.between (-9) 0;
        default = -1.5;
        description = "True peak ceiling in dBTP.";
      };

      loudnessRange = lib.mkOption {
        type = lib.types.numbers.positive;
        default = 11;
        description = "Target loudness range in LU.";
      };
    };

    mountIntoTunarr = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Bind-mount the directory read-only into the tunarr container.";
    };
  };

  config = {
    environment.systemPackages = [ fetchScript ];

    systemd.tmpfiles.rules = [
      "d ${cfg.directory} 0755 root root -"
    ];

    systemd.services.adbreaks-fetch = lib.mkIf (cfg.playlists != { }) {
      description = "Fetch commercial break clips from YouTube playlists";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ cfg.directory ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe fetchScript;
        StateDirectory = "adbreaks";
        CacheDirectory = "adbreaks";
        Environment = [
          "XDG_CACHE_HOME=/var/cache/adbreaks"
          "HOME=/var/cache/adbreaks"
        ];
        ReadWritePaths = [ cfg.directory ];
        UMask = "0022";
        TimeoutStartSec = "2h";
        Nice = 15;
        CPUSchedulingPolicy = "batch";
        IOSchedulingClass = "idle";

        CapabilityBoundingSet = [ "" ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallErrorNumber = "EPERM";
        SystemCallFilter = [ "@system-service" ];
      };
    };

    systemd.timers.adbreaks-fetch = lib.mkIf (cfg.playlists != { }) {
      description = "Periodic commercial break clip sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "20m";
        AccuracySec = "5m";
      };
    };

    virtualisation.oci-containers.containers = lib.mkIf cfg.mountIntoTunarr {
      tunarr.volumes = [ "${cfg.directory}:${cfg.directory}:ro" ];
    };
  };
}
