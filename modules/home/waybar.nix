{ pkgs, ... }:

let
  recordingStatus = pkgs.writeShellScript "waybar-recording" ''
    pidfile="$XDG_RUNTIME_DIR/niri-record.pid"
    if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
      printf '{"text":"● REC","class":"recording"}\n'
    else
      printf '{"text":""}\n'
    fi
  '';

  notificationFeed = pkgs.writeShellScript "waybar-notification-feed" ''
    printf '{"text":""}\n'

    ${pkgs.coreutils}/bin/stdbuf -oL ${pkgs.dbus}/bin/dbus-monitor \
      "interface='org.freedesktop.Notifications',member='Notify'" 2>/dev/null \
      | ${pkgs.gawk}/bin/awk '
          function jesc(s) {
            gsub(/\\/, "\\\\", s)
            gsub(/"/, "\\\"", s)
            gsub(/\n/, " ", s)
            gsub(/\t/, " ", s)
            return s
          }
          # Notify args in order: string app_name, uint32 id, string app_icon,
          # string summary, string body, ... -> summary is string #3, body #4.
          /member=Notify/ { n = 0; summary = ""; body = ""; cap = 1; next }
          cap && /^[[:space:]]*string/ {
            n++
            line = $0
            sub(/^[[:space:]]*string "/, "", line)
            sub(/"[[:space:]]*$/, "", line)
            if (n == 3) summary = line
            else if (n == 4) {
              body = line
              text = summary
              if (body != "") text = summary "  " body
              if (length(text) > 64) text = substr(text, 1, 61) "..."
              tip = summary
              if (body != "") tip = summary ": " body
              printf "{\"text\":\"%s\",\"tooltip\":\"%s\",\"class\":\"active\"}\n", jesc(text), jesc(tip)
              fflush()
              cap = 0
            }
          }
        '
  '';

in
{
  home.file.".config/waybar/style.css".source = ./waybar/style.css;

  programs.waybar = {
    enable = true;
    settings = [
      {
        layer = "top";
        position = "bottom";
        spacing = 0;
        height = 0;

        modules-left = [
          "niri/workspaces"
          "tray"
          "custom/flake"
          "custom/notification"
        ];

        modules-center = [
          "clock#secondary"
          "clock"
          "custom/weather"
        ];

        modules-right = [
          "custom/recording"
          "custom/check"
          "custom/backup"
          "cpu"
          "memory"
          "network"
          "pulseaudio"
          "battery"
        ];

        tray = {
          "show-passive-items" = true;
          "spacing" = 10;
          "tooltip" = false;
        };

        clock = {
          "format" = "  {:%I:%M:%S %p}";
          "interval" = 1;
          "tooltip" = false;
        };

        "clock#secondary" = {
          "format" = "  {:%a, %d %b %Y}";
          "interval" = 1;
          "tooltip" = false;
        };

        cpu = {
          "format" = "  {usage}%";
          "interval" = 1;

          states = {
            "critical" = 90;
          };
        };

        memory = {
          "format" = "  {percentage}%";
          "interval" = 2;

          states = {
            "critical" = 80;
          };
        };

        network = {
          "format-wifi" = "  {bandwidthDownBytes} {bandwidthUpBytes}";
          "format-ethernet" = "  {bandwidthDownBytes} {bandwidthUpBytes}";
          "format-disconnected" = "󱚼  no network";
          "interval" = 1;
          "tooltip" = false;
        };

        pulseaudio = {
          "scroll-step" = 5;
          "max-volume" = 150;
          "format" = "  {volume}%";
          "format-bluetooth" = "  {volume}%";
          "nospacing" = 1;
          "on-click" = "pavucontrol";
          "tooltip" = false;
        };

        battery = {
          "bat" = "BAT0";
          "format" = "  {capacity}%";
        };

        "custom/notification" = {
          "exec" = "${notificationFeed}";
          "return-type" = "json";
          "on-click" = "swaync-client -t -sw";
          "on-click-right" = "swaync-client -d -sw";
          "escape" = true;
          "max-length" = 70;
          "tooltip" = true;
        };

        "custom/weather" = {
          "exec" = "curl -s 'wttr.in/Bielefeld?format=1'";
          "interval" = 600;
        };

        "custom/backup" = {
          "exec-if" = "systemctl is-active --quiet borgbackup-job-home.service";
          "exec" = "echo '󰋊'";
          "interval" = 5;
          "tooltip" = false;
        };

        "custom/flake" = {
          "exec-if" =
            "git -C /home/aleph/flake status --porcelain 2>/dev/null | grep -q . || [ \"$(git -C /home/aleph/flake rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)\" != 0 ]";
          "exec" = "echo '󰘬'";
          "interval" = 15;
          "tooltip" = false;
        };

        "custom/check" = {
          "exec-if" = "systemctl is-failed --quiet borgbackup-check-home.service";
          "exec" = "echo '󰀦 backup check failed'";
          "interval" = 30;
          "tooltip" = false;
        };

        "custom/recording" = {
          "exec" = "${recordingStatus}";
          "return-type" = "json";
          "interval" = 1;
          "on-click" = "niri-record";
          "tooltip" = false;
        };
      }
    ];
  };
}
