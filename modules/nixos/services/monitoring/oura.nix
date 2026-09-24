{
  config,
  pkgs,
  ...
}:

let
  # Read back by the node exporter's textfile collector. Only the exporter's
  # own health gauges land in prometheus (for alerting); the actual vitals go
  # into victoriametrics below with their real timestamps.
  textfileDir = "/var/lib/oura-metrics";

  vmUrl = "http://127.0.0.1:8428";

  # Turns the raw Oura API responses into victoriametrics import lines
  # ("name{labels} value timestamp_ms"). Every sample keeps the moment it was
  # actually measured, so late syncs from the ring land in the right place on
  # the graphs instead of at ingestion time. Re-importing the same samples is
  # idempotent: victoriametrics deduplicates identical points.
  importScript = pkgs.writeText "oura-metrics-import.jq" ''
    def line($name; $value; $ts):
      if $value == null then empty else "\($name) \($value) \($ts)" end;

    # RFC3339 with offset -> epoch milliseconds. jq's fromdateiso8601 only
    # accepts Z, so the offset is parsed by hand. Records with timestamps
    # that do not match are skipped (the "as" binds over an empty stream).
    def iso_ms:
      capture("^(?<d>\\d{4}-\\d{2}-\\d{2})T(?<t>\\d{2}:\\d{2}:\\d{2})(\\.\\d+)?(?<z>Z|[+-]\\d{2}:?\\d{2})?")
      | ((.d + "T" + .t + "Z") | fromdateiso8601) as $utc
      | (if .z == null or .z == "Z" then 0
         else (.z
           | capture("(?<s>[+-])(?<h>\\d{2}):?(?<m>\\d{2})")
           | (if .s == "+" then -1 else 1 end) * ((.h | tonumber) * 3600 + (.m | tonumber) * 60))
         end) as $offset
      | ($utc + $offset) * 1000;

    # Daily summaries only carry a date; pin them to noon UTC.
    def day_ms: ((. + "T12:00:00Z") | fromdateiso8601) * 1000;

    def status_code:
      { "awake": 1, "rest": 2, "sleep": 3, "session": 4, "live": 5 }[.] // 0;

    ( ($rawHeartrate[0] // [])[]
      | ((.timestamp // "") | iso_ms?) as $t
      | line("oura_heart_rate_bpm"; .bpm; $t),
        line("oura_heart_rate_status"; ((.source // "unknown") | status_code); $t)
    ),
    ( ($rawReadiness[0] // [])[]
      | ((.day // "") | day_ms?) as $t
      | line("oura_readiness_score"; .score; $t),
        line("oura_temperature_deviation_celsius"; .temperature_deviation; $t)
    ),
    ( ($rawDailySleep[0] // [])[]
      | ((.day // "") | day_ms?) as $t
      | line("oura_sleep_score"; .score; $t)
    ),
    ( ($rawActivity[0] // [])[]
      | ((.day // "") | day_ms?) as $t
      | line("oura_activity_score"; .score; $t),
        line("oura_activity_steps"; .steps; $t),
        line("oura_activity_active_calories"; .active_calories; $t)
    ),
    ( ($rawSessions[0] // [])[]
      | select(.type == "long_sleep")
      | ((.bedtime_end // "") | iso_ms?) as $t
      | line("oura_sleep_total_duration_seconds"; .total_sleep_duration; $t),
        line("oura_sleep_deep_duration_seconds"; .deep_sleep_duration; $t),
        line("oura_sleep_rem_duration_seconds"; .rem_sleep_duration; $t),
        line("oura_sleep_light_duration_seconds"; .light_sleep_duration; $t),
        line("oura_sleep_awake_duration_seconds"; .awake_time; $t),
        line("oura_sleep_efficiency_percent"; .efficiency; $t),
        line("oura_sleep_average_hrv_milliseconds"; .average_hrv; $t),
        line("oura_sleep_lowest_heart_rate_bpm"; .lowest_heart_rate; $t),
        line("oura_sleep_average_heart_rate_bpm"; .average_heart_rate; $t)
    )
  '';

  metricsScript = pkgs.writeShellApplication {
    name = "oura-metrics";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
    ];
    text = ''
      api="https://api.ouraring.com/v2/usercollection"
      vm="${vmUrl}"
      out="${textfileDir}/oura.prom"

      # Regular timer runs re-fetch a trailing window, because the ring only
      # syncs to Oura's cloud when the phone app feels like it - data for
      # "yesterday" keeps trickling in for a while. oura-backfill sets this
      # much higher to import the whole account history.
      lookback_days="''${OURA_LOOKBACK_DAYS:-3}"

      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      fail=0
      now="$(date +%s)"
      start=$(( now - lookback_days * 86400 ))

      # paginate <pages-file> <collection> [curl query args...]
      # Follows Oura's next_token pagination, appending every page's .data
      # array to the pages file. Pages move through files rather than shell
      # variables: heart rate data quickly outgrows a process argument.
      paginate() {
        pages="$1"
        path="$2"
        shift 2

        next=""
        while : ; do
          extra=()
          if [ -n "$next" ]; then
            extra=(--data-urlencode "next_token=$next")
          fi
          if ! curl --get --fail --silent --show-error --max-time 120 \
              --retry 2 --retry-delay 5 \
              --header "Authorization: Bearer $OURA_TOKEN" \
              --output "$tmp/page.json" \
              "$@" "''${extra[@]}" "$api/$path"; then
            return 1
          fi
          jq -c '.data // []' "$tmp/page.json" >> "$pages"
          next="$(jq -r '.next_token // empty' "$tmp/page.json")"
          [ -n "$next" ] || break
        done
      }

      # fetch_range <collection> <outfile> <date|datetime>
      # Walks the lookback window in 30-day chunks (long ranges upset some
      # Oura endpoints) and merges everything into one array. A failed
      # endpoint leaves an empty array behind so the others still make it
      # out; oura_fetch_success records the miss.
      fetch_range() {
        path="$1"
        outfile="$2"
        kind="$3"

        allpages="$tmp/$path.pages"
        : > "$allpages"

        ok=1
        wstart=$start
        while [ "$wstart" -lt "$now" ]; do
          wend=$(( wstart + 30 * 86400 ))
          if [ "$wend" -gt "$now" ]; then
            wend=$(( now + 3600 ))
          fi
          if [ "$kind" = "datetime" ]; then
            paginate "$allpages" "$path" \
              --data-urlencode "start_datetime=$(date -u -d "@$wstart" +%Y-%m-%dT%H:%M:%SZ)" \
              --data-urlencode "end_datetime=$(date -u -d "@$wend" +%Y-%m-%dT%H:%M:%SZ)" \
              || { ok=0; break; }
          else
            paginate "$allpages" "$path" \
              --data-urlencode "start_date=$(date -u -d "@$wstart" +%F)" \
              --data-urlencode "end_date=$(date -u -d "@$wend" +%F)" \
              || { ok=0; break; }
          fi
          wstart=$wend
        done

        if [ "$ok" -eq 1 ]; then
          jq -c -s 'add // []' "$allpages" > "$outfile"
        else
          echo "oura-metrics: could not fetch $path" >&2
          fail=1
          echo '[]' > "$outfile"
        fi
      }

      fetch_range heartrate "$tmp/heartrate.json" datetime
      fetch_range daily_readiness "$tmp/readiness.json" date
      fetch_range daily_sleep "$tmp/daily-sleep.json" date
      fetch_range daily_activity "$tmp/activity.json" date
      fetch_range sleep "$tmp/sleep.json" date

      jq -r -n \
        --slurpfile rawHeartrate "$tmp/heartrate.json" \
        --slurpfile rawReadiness "$tmp/readiness.json" \
        --slurpfile rawDailySleep "$tmp/daily-sleep.json" \
        --slurpfile rawActivity "$tmp/activity.json" \
        --slurpfile rawSessions "$tmp/sleep.json" \
        -f ${importScript} > "$tmp/import.txt"

      if [ -s "$tmp/import.txt" ]; then
        if ! curl --fail --silent --show-error --max-time 300 \
            --data-binary @"$tmp/import.txt" \
            "$vm/api/v1/import/prometheus"; then
          echo "oura-metrics: could not import into victoriametrics" >&2
          fail=1
        fi
      fi

      # Health snapshot for prometheus (via the node exporter's textfile
      # collector), which is what the OuraDataStale alert watches.
      {
        echo "# HELP oura_fetch_success Whether the last run fetched and imported every Oura endpoint."
        echo "# TYPE oura_fetch_success gauge"
        echo "oura_fetch_success $((1 - fail))"
        echo "# HELP oura_fetch_timestamp_seconds When the exporter last ran."
        echo "# TYPE oura_fetch_timestamp_seconds gauge"
        echo "oura_fetch_timestamp_seconds $(date +%s)"
      } > "$out.tmp"
      chmod 0644 "$out.tmp"
      mv "$out.tmp" "$out"
    '';
  };

  # One-shot import of the whole account history (or any custom start date).
  # Reuses the exact same unit sandbox and secret as the timer runs.
  backfillScript = pkgs.writeShellApplication {
    name = "oura-backfill";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # usage: oura-backfill [start-date]   (default 2015-01-01, needs root)
      startdate="''${1:-2015-01-01}"
      days=$(( ( $(date +%s) - $(date -d "$startdate" +%s) ) / 86400 + 1 ))

      echo "importing oura history since $startdate ($days days) ..."
      exec systemd-run --wait --pipe --collect --unit=oura-backfill \
        --property=Type=oneshot \
        --property=User=oura-metrics \
        --property=Group=oura-metrics \
        --property=StateDirectory=oura-metrics \
        --property=EnvironmentFile=${config.age.secrets.oura-env.path} \
        --setenv=OURA_LOOKBACK_DAYS="$days" \
        ${metricsScript}/bin/oura-metrics
    '';
  };
in
{
  # Personal access token for the Oura v2 API: OURA_TOKEN=<token>
  age.secrets.oura-env.file = ../../../../hosts/shimmers/secrets/oura-env.age;

  # Long-retention store for the ring data. Prometheus is unsuitable here:
  # Oura data arrives hours late in batches, and prometheus cannot ingest
  # samples with historical timestamps (no out-of-order window support in the
  # NixOS module). victoriametrics speaks PromQL, so grafana treats it as
  # just another prometheus datasource.
  services.victoriametrics = {
    enable = true;
    listenAddress = "127.0.0.1:8428";
    retentionPeriod = "50y";
    # Every exporter run re-imports a trailing window, so identical samples
    # (same series, same timestamp) arrive over and over. This drops the
    # duplicates at query time and permanently during background merges.
    extraOptions = [ "-dedup.minScrapeInterval=1ms" ];
  };

  # A static user rather than DynamicUser: with DynamicUser the state
  # directory really lives under /var/lib/private (0700 root), which the
  # node exporter's own unprivileged user cannot traverse, so the textfile
  # collector would never see oura.prom.
  users.users.oura-metrics = {
    isSystemUser = true;
    group = "oura-metrics";
  };
  users.groups.oura-metrics = { };

  systemd.services.oura-metrics = {
    description = "oura ring metrics for victoriametrics";
    after = [
      "network-online.target"
      "victoriametrics.service"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${metricsScript}/bin/oura-metrics";
      EnvironmentFile = [ config.age.secrets.oura-env.path ];

      User = "oura-metrics";
      Group = "oura-metrics";
      StateDirectory = "oura-metrics";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };

  systemd.timers.oura-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      RandomizedDelaySec = "30s";
      Persistent = true;
    };
  };

  environment.systemPackages = [ backfillScript ];

  services.prometheus.exporters.node.extraFlags = [
    "--collector.textfile.directory=${textfileDir}"
  ];

  services.prometheus.rules = [
    (builtins.toJSON {
      groups = [
        {
          name = "oura";
          rules = [
            {
              alert = "OuraDataStale";
              # Fires both when the API keeps erroring (fetch_success stays 0)
              # and when the timer stops running entirely (timestamp ages out).
              expr = "(max(oura_fetch_success) == 0) or (time() - max(oura_fetch_timestamp_seconds) > 3600)";
              for = "30m";
              labels.severity = "warning";
              annotations = {
                summary = "Oura ring data has stopped updating.";
                resolved = "Oura ring data is flowing again.";
              };
            }
          ];
        }
      ];
    })
  ];
}
