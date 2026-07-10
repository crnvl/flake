{ pkgs, lib, ... }:

let
  recordingStatus = pkgs.writeShellScript "waybar-recording" ''
    pidfile="$XDG_RUNTIME_DIR/niri-record.pid"
    if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
      printf '{"text":"● REC","class":"recording"}\n'
    else
      printf '{"text":""}\n'
    fi
  '';

  # Writes the latest notification text to a state file (run as a user service).
  notificationWriter = pkgs.writeShellScript "notification-feed-writer" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.dbus
        pkgs.gawk
      ]
    }
    statefile="$XDG_RUNTIME_DIR/waybar-notification"
    : > "$statefile"

    stdbuf -oL dbus-monitor "interface='org.freedesktop.Notifications',member='Notify'" 2>/dev/null \
      | awk '
          function clean(s) { gsub(/\n/, " ", s); gsub(/\t/, " ", s); return s }
          # Notify strings in order: app_name, app_icon, summary(#3), body(#4)
          /member=Notify/ { n = 0; summary = ""; body = ""; cap = 1; next }
          cap && /^[[:space:]]*string/ {
            n++
            line = $0
            sub(/^[[:space:]]*string "/, "", line)
            sub(/"[[:space:]]*$/, "", line)
            if (n == 3) summary = line
            else if (n == 4) {
              body = line
              msg = summary
              if (body != "") msg = summary "  —  " body
              print clean(msg)
              fflush()
              cap = 0
            }
          }
        ' \
      | while IFS= read -r line; do
          printf '%s' "$line" > "$statefile.tmp" && mv "$statefile.tmp" "$statefile"
        done
  '';

  # Scrolls the current message inside a fixed-width window for waybar.
  # Flushes every frame (bash buffers stdout on a pipe) and pauses after each
  # full scroll cycle so the start of the message is readable.
  notificationTicker = pkgs.writeScript "notification-feed-ticker" ''
    #!${pkgs.python3}/bin/python3
    import json
    import os
    import sys
    import time

    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    statefile = os.path.join(runtime, "waybar-notification")
    width = 42
    gap = "          "
    step = 0.25
    pause = 3.0
    cur = ""
    offset = 0

    sys.stdout.write('{"text":""}\n')
    sys.stdout.flush()

    while True:
        try:
            with open(statefile) as f:
                msg = f.read().strip()
        except OSError:
            msg = ""

        if msg != cur:
            cur = msg
            offset = 0

        if not cur:
            payload = {"text": ""}
            delay = 0.5
        elif len(cur) <= width:
            payload = {"text": cur.ljust(width), "tooltip": cur, "class": "active"}
            delay = 1.0
        else:
            loop = cur + gap
            doubled = loop + loop
            start = offset % len(loop)
            payload = {
                "text": doubled[start:start + width],
                "tooltip": cur,
                "class": "active",
            }
            # Pause when a full cycle brings us back to the start.
            delay = pause if start == 0 else step
            offset += 1

        sys.stdout.write(json.dumps(payload) + "\n")
        sys.stdout.flush()
        time.sleep(delay)
  '';

in
{
  systemd.user.services.notification-feed = {
    Unit = {
      Description = "Feed the latest desktop notification to waybar";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      ExecStart = "${notificationWriter}";
      Restart = "on-failure";
    };
  };

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
          "exec" = "${notificationTicker}";
          "return-type" = "json";
          "on-click" = "swaync-client -t -sw";
          "on-click-right" = "swaync-client -d -sw";
          "escape" = true;
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
