{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.tagesschau;

  # Progressive stream keys the API exposes, best first. Picking one also
  # allows falling back to the lower ones if a broadcast lacks it.
  fallbacks = {
    h264xl = [
      "h264xl"
      "h264m"
      "h264s"
    ];
    h264m = [
      "h264m"
      "h264s"
    ];
    h264s = [ "h264s" ];
  };

  streamExpr = lib.concatMapStringsSep " // " (k: ".streams.${k}") fallbacks.${cfg.quality};

  fetchScript = pkgs.writeShellApplication {
    name = "tagesschau-fetch";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      findutils
      gawk
      ffmpeg-headless
    ];
    text = ''
      api="https://www.tagesschau.de/api2u/channels"
      agent="tagesschau-fetch/1 (personal, non-commercial use)"

      dir="${cfg.directory}"
      target="$dir/${cfg.filename}"
      state="''${STATE_DIRECTORY:-/var/lib/tagesschau-fetch}/state.json"

      tmp=""
      meta="$(mktemp)"
      trap 'rm -f "$meta" "''${tmp:-}"' EXIT

      # The API asks for no more than 60 requests per hour; we make two a day.
      curl --fail --silent --show-error --location --compressed \
        --retry 5 --retry-delay 15 --retry-all-errors --max-time 60 \
        --user-agent "$agent" \
        --output "$meta" "$api"

      # The channel list carries one slot for the 20 Uhr edition, tagged as
      # such in the tracking metadata. Everything else (100 Sekunden, the
      # 00:20 repeat, tagesthemen, ...) is filtered out here.
      selection="$(jq -r '
        def is20uhr:
          any((.tracking // [])[];
              (((.sid // "") | contains("tagesschau_20_uhr"))
               or ((.c5 // "") | contains("/tagesschau_20_uhr/"))));

        [ (.channels // [])[]
          | select(.type == "video")
          | select(is20uhr)
          | { id: (.sophoraId // ""), date: (.date // ""), url: (${streamExpr}) }
          | select(.url != null and .url != "")
        ]
        | sort_by(.date)
        | last
        | if . == null then "" else [ .id, .date, .url ] | @tsv end
      ' "$meta")"

      if [ -z "$selection" ]; then
        echo "no 20 Uhr tagesschau with a ${cfg.quality} stream in the channel list" >&2
        exit 1
      fi

      IFS=$'\t' read -r id broadcast url <<< "$selection"
      echo "latest 20 Uhr edition: $id ($broadcast)"

      if epoch="$(date -d "$broadcast" +%s 2>/dev/null)"; then
        age_hours=$(( ( $(date +%s) - epoch ) / 3600 ))
        if [ "$age_hours" -gt 36 ]; then
          echo "warning: newest edition is ''${age_hours}h old, the feed may be stale" >&2
        fi
      fi

      if [ -f "$target" ] && [ -f "$state" ] &&
         [ "$(jq -r '.id // ""' "$state")" = "$id" ]; then
        echo "$id is already in place, nothing to do"
        exit 0
      fi

      mkdir -p "$dir"
      tmp="$dir/.''${id}.part"
      rm -f "$tmp"

      echo "downloading $url"
      curl --fail --silent --show-error --location \
        --retry 5 --retry-delay 15 --retry-all-errors --max-time 1800 \
        --user-agent "$agent" \
        --output "$tmp" "$url"

      # Only swap in something that actually decodes and is roughly a full
      # broadcast, so a truncated download never replaces yesterday's file.
      duration="$(ffprobe -v error -show_entries format=duration \
        -of default=nw=1:nk=1 "$tmp")"
      if ! awk -v d="$duration" 'BEGIN { exit !(d >= 300) }'; then
        echo "download is only ''${duration}s long, keeping the existing file" >&2
        exit 1
      fi

      mv -f "$tmp" "$target"
      tmp=""
      chmod 0644 "$target" 2>/dev/null || true

      # Exactly one video in here, ever.
      find "$dir" -mindepth 1 -maxdepth 1 -type f ! -name "${cfg.filename}" -delete

      jq -n \
        --arg id "$id" \
        --arg broadcast "$broadcast" \
        --arg source "$url" \
        --arg file "$target" \
        --argjson duration "$duration" \
        '{
           id: $id,
           broadcast: $broadcast,
           source: $source,
           file: $file,
           duration: $duration,
           fetched: (now | todate)
         }' > "$state"

      echo "installed $target (''${duration}s)"
    '';
  };
in
{
  options.my.tagesschau = {
    directory = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/tagesschau";
      description = ''
        Directory holding the video. It is trimmed to exactly one file after
        every successful run, so it never grows.
      '';
    };

    filename = lib.mkOption {
      type = lib.types.str;
      default = "tagesschau-2000.mp4";
      description = ''
        Stable name for the video, so a Tunarr program pointing at it keeps
        resolving after the content underneath is swapped out.
      '';
    };

    quality = lib.mkOption {
      type = lib.types.enum [
        "h264xl"
        "h264m"
        "h264s"
      ];
      default = "h264xl";
      description = "Preferred progressive stream, falling back to lower ones.";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 19:00:00";
      description = ''
        OnCalendar expression, in local time. Note that at 19:00 the newest
        20 Uhr edition on offer is the previous day's.
      '';
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

    systemd.services.tagesschau-fetch = {
      description = "Fetch the latest 20 Uhr tagesschau";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ cfg.directory ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe fetchScript;
        StateDirectory = "tagesschau-fetch";
        ReadWritePaths = [ cfg.directory ];
        UMask = "0022";

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

    systemd.timers.tagesschau-fetch = {
      description = "Daily 20 Uhr tagesschau download";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "10m";
        AccuracySec = "1m";
      };
    };

    virtualisation.oci-containers.containers = lib.mkIf cfg.mountIntoTunarr {
      tunarr.volumes = [ "${cfg.directory}:${cfg.directory}:ro" ];
    };
  };
}
