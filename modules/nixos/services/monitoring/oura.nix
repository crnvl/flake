{
  config,
  pkgs,
  ...
}:

let
  # Written by the oura-metrics timer below and read back by the node
  # exporter's textfile collector, so the metrics ride along on the existing
  # "node" scrape job instead of needing a dedicated exporter port.
  textfileDir = "/var/lib/oura-metrics";

  # Boils the raw Oura API responses down to "latest known value" gauges.
  # Metrics whose source data is missing (ring not synced yet, empty window)
  # are simply omitted, so panels show "No data" instead of stale zeros.
  renderScript = pkgs.writeText "oura-metrics-render.jq" ''
    def gauge($name; $help; $value):
      if $value == null then []
      else
        [ "# HELP \($name) \($help)",
          "# TYPE \($name) gauge",
          "\($name) \($value)" ]
      end;

    def labeled($name; $help; $labels; $value):
      if $value == null then []
      else
        [ "# HELP \($name) \($help)",
          "# TYPE \($name) gauge",
          "\($name){\($labels)} \($value)" ]
      end;

    ($rawHeartrate[0] // []) as $heartrate
    | ($rawReadiness[0] // []) as $readiness
    | ($rawDailySleep[0] // []) as $dailySleep
    | ($rawActivity[0] // []) as $activity
    | ($rawSessions[0] // []) as $sessions
    | (if ($heartrate | length) > 0 then ($heartrate | max_by(.timestamp)) else null end) as $pulse
    | (if ($readiness | length) > 0 then ($readiness | max_by(.day)) else null end) as $ready
    | ([ $readiness[] | select(.temperature_deviation != null) ]
       | if length > 0 then max_by(.day) else null end) as $temp
    | (if ($dailySleep | length) > 0 then ($dailySleep | max_by(.day)) else null end) as $restScore
    | (if ($activity | length) > 0 then ($activity | max_by(.day)) else null end) as $moved
    # Prefer the main long sleep; naps only count when there is nothing else.
    | (([ $sessions[] | select(.type == "long_sleep") ]) as $nights
       | (if ($nights | length) > 0 then $nights else $sessions end)
       | if length > 0 then max_by(.bedtime_end) else null end) as $night
    | ( gauge("oura_heart_rate_bpm"; "Most recent heart rate sample from the ring."; $pulse.bpm)
      + labeled("oura_heart_rate_source_info";
          "Origin of the most recent heart rate sample, which doubles as wearer status.";
          "source=\"\($pulse.source // "unknown")\"";
          if $pulse == null then null else 1 end)
      + gauge("oura_heart_rate_sample_timestamp_seconds";
          "When the most recent heart rate sample was taken."; $hrSampleTime)
      + gauge("oura_temperature_deviation_celsius";
          "Body temperature deviation from baseline, as of last night."; $temp.temperature_deviation)
      + gauge("oura_readiness_score"; "Daily readiness score (0-100)."; $ready.score)
      + gauge("oura_sleep_score"; "Daily sleep score (0-100)."; $restScore.score)
      + gauge("oura_activity_score"; "Daily activity score (0-100)."; $moved.score)
      + gauge("oura_activity_steps"; "Steps taken today."; $moved.steps)
      + gauge("oura_activity_active_calories"; "Active calories burned today."; $moved.active_calories)
      + gauge("oura_sleep_total_duration_seconds"; "Total sleep during the latest night."; $night.total_sleep_duration)
      + gauge("oura_sleep_deep_duration_seconds"; "Deep sleep during the latest night."; $night.deep_sleep_duration)
      + gauge("oura_sleep_rem_duration_seconds"; "REM sleep during the latest night."; $night.rem_sleep_duration)
      + gauge("oura_sleep_light_duration_seconds"; "Light sleep during the latest night."; $night.light_sleep_duration)
      + gauge("oura_sleep_awake_duration_seconds"; "Time awake in bed during the latest night."; $night.awake_time)
      + gauge("oura_sleep_efficiency_percent"; "Sleep efficiency during the latest night."; $night.efficiency)
      + gauge("oura_sleep_average_hrv_milliseconds"; "Average HRV during the latest night."; $night.average_hrv)
      + gauge("oura_sleep_lowest_heart_rate_bpm"; "Lowest heart rate during the latest night."; $night.lowest_heart_rate)
      + gauge("oura_sleep_average_heart_rate_bpm"; "Average heart rate during the latest night."; $night.average_heart_rate)
      + gauge("oura_fetch_success"; "Whether the last run fetched every Oura endpoint."; $fetchSuccess)
      + gauge("oura_fetch_timestamp_seconds"; "When the exporter last ran."; $fetchTime)
      )
    | .[]
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
      out="${textfileDir}/oura.prom"

      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      fail=0

      # fetch_all <collection> <outfile> [curl query args...]
      # Follows Oura's next_token pagination and merges every page's .data
      # into one array. A failed endpoint leaves an empty array behind so the
      # other metrics still make it out; oura_fetch_success records the miss.
      fetch_all() {
        path="$1"
        outfile="$2"
        shift 2

        merged="[]"
        next=""
        while : ; do
          extra=()
          if [ -n "$next" ]; then
            extra=(--data-urlencode "next_token=$next")
          fi
          if ! page="$(curl --get --fail --silent --show-error --max-time 60 \
              --retry 2 --retry-delay 5 \
              --header "Authorization: Bearer $OURA_TOKEN" \
              "$@" "''${extra[@]}" "$api/$path")"; then
            echo "oura-metrics: could not fetch $path" >&2
            fail=1
            merged="[]"
            break
          fi
          merged="$(jq -c --argjson acc "$merged" '$acc + (.data // [])' <<< "$page")"
          next="$(jq -r '.next_token // empty' <<< "$page")"
          [ -n "$next" ] || break
        done
        printf '%s' "$merged" > "$outfile"
      }

      # The ring only syncs when the phone app feels like it, so the windows
      # are generous: the newest sample inside them is still "the latest".
      fetch_all heartrate "$tmp/heartrate.json" \
        --data-urlencode "start_datetime=$(date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
        --data-urlencode "end_datetime=$(date -u -d '1 hour' +%Y-%m-%dT%H:%M:%SZ)"

      day_start="$(date -u -d '7 days ago' +%F)"
      day_end="$(date -u +%F)"
      fetch_all daily_readiness "$tmp/readiness.json" \
        --data-urlencode "start_date=$day_start" --data-urlencode "end_date=$day_end"
      fetch_all daily_sleep "$tmp/daily-sleep.json" \
        --data-urlencode "start_date=$day_start" --data-urlencode "end_date=$day_end"
      fetch_all daily_activity "$tmp/activity.json" \
        --data-urlencode "start_date=$day_start" --data-urlencode "end_date=$day_end"
      fetch_all sleep "$tmp/sleep.json" \
        --data-urlencode "start_date=$day_start" --data-urlencode "end_date=$day_end"

      # RFC3339 offsets are easier for date(1) than for jq, so the sample
      # timestamp is converted out here and handed in ready-made.
      hr_sample=null
      hr_ts="$(jq -r 'if length > 0 then max_by(.timestamp).timestamp else empty end' "$tmp/heartrate.json")"
      if [ -n "$hr_ts" ]; then
        hr_sample="$(date -d "$hr_ts" +%s)"
      fi

      jq -r -n \
        --slurpfile rawHeartrate "$tmp/heartrate.json" \
        --slurpfile rawReadiness "$tmp/readiness.json" \
        --slurpfile rawDailySleep "$tmp/daily-sleep.json" \
        --slurpfile rawActivity "$tmp/activity.json" \
        --slurpfile rawSessions "$tmp/sleep.json" \
        --argjson hrSampleTime "$hr_sample" \
        --argjson fetchTime "$(date +%s)" \
        --argjson fetchSuccess "$((1 - fail))" \
        -f ${renderScript} > "$out.tmp"

      chmod 0644 "$out.tmp"
      mv "$out.tmp" "$out"
    '';
  };
in
{
  # Personal access token for the Oura v2 API: OURA_TOKEN=<token>
  age.secrets.oura-env.file = ../../../../hosts/shimmers/secrets/oura-env.age;

  systemd.services.oura-metrics = {
    description = "oura ring metrics for prometheus";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${metricsScript}/bin/oura-metrics";
      EnvironmentFile = [ config.age.secrets.oura-env.path ];

      DynamicUser = true;
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
