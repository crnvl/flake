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
  # Flushes every frame, pauses at the start of each cycle, keeps a constant
  # width (blank when idle), and clears the text 30s after the last update.
  notificationTicker = pkgs.writeScript "notification-feed-ticker" ''
    #!${pkgs.python3}/bin/python3
    import json
    import os
    import sys
    import time

    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    statefile = os.path.join(runtime, "waybar-notification")
    width = 42
    gap = "     •     "
    step = 0.25
    pause = 3.0
    timeout = 30.0
    cur = ""
    offset = 0
    shown_at = 0.0
    expired = False

    while True:
        try:
            with open(statefile) as f:
                msg = f.read().strip()
        except OSError:
            msg = ""

        if msg != cur:
            cur = msg
            offset = 0
            shown_at = time.time()
            expired = False

        if cur and not expired and time.time() - shown_at > timeout:
            expired = True

        if not cur or expired:
            text = " " * width
            tip = ""
            delay = 0.5
        elif len(cur) <= width:
            text = cur.ljust(width)
            tip = cur
            delay = 1.0
        else:
            loop = cur + gap
            doubled = loop + loop
            start = offset % len(loop)
            text = doubled[start:start + width]
            tip = cur
            delay = pause if start == 0 else step
            offset += 1

        payload = {"text": text, "tooltip": tip, "class": "active"}
        sys.stdout.write(json.dumps(payload) + "\n")
        sys.stdout.flush()
        time.sleep(delay)
  '';

  # Adjusts the default sink and fires a notification (shown in the ticker).
  # Exposed on PATH as `volume-notify` so niri media keys can use it too.
  volumeControl = pkgs.writeShellScriptBin "volume-notify" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.wireplumber
        pkgs.libnotify
        pkgs.gawk
        pkgs.gnugrep
        pkgs.coreutils
      ]
    }
    sink="@DEFAULT_AUDIO_SINK@"
    case "$1" in
      up)   wpctl set-volume -l 1.5 "$sink" 5%+ ;;
      down) wpctl set-volume "$sink" 5%- ;;
      mute) wpctl set-mute "$sink" toggle ;;
    esac

    out=$(wpctl get-volume "$sink")
    pct=$(printf '%s' "$out" | awk '{printf "%d", $2 * 100}')
    if printf '%s' "$out" | grep -q MUTED; then
      body="muted"
    else
      body="$pct%"
    fi
    notify-send -a Volume -t 2000 \
      -h string:x-canonical-private-synchronous:volume \
      "Volume" "$body"
  '';

  # Adjusts the backlight and fires a notification (shown in the ticker).
  # Exposed on PATH as `brightness-notify` for the niri brightness keys.
  brightnessControl = pkgs.writeShellScriptBin "brightness-notify" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.brightnessctl
        pkgs.libnotify
        pkgs.gawk
        pkgs.coreutils
      ]
    }
    case "$1" in
      up)   brightnessctl --class=backlight set 10%+ >/dev/null ;;
      down) brightnessctl --class=backlight set 10%- >/dev/null ;;
    esac
    pct=$(brightnessctl --class=backlight -m | awk -F, '{print $4}')
    notify-send -a Brightness -t 2000 \
      -h string:x-canonical-private-synchronous:brightness \
      "Brightness" "$pct"
  '';

  # Notifies (into the ticker) when the battery crosses low thresholds.
  batteryMonitor = pkgs.writeShellScript "battery-monitor" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.libnotify
        pkgs.coreutils
      ]
    }
    bat=/sys/class/power_supply/BAT0
    last=100
    while true; do
      cap=$(cat "$bat/capacity" 2>/dev/null || echo 100)
      status=$(cat "$bat/status" 2>/dev/null || echo Unknown)
      if [ "$status" = "Discharging" ]; then
        for t in 25 10 5; do
          if [ "$cap" -le "$t" ] && [ "$last" -gt "$t" ]; then
            notify-send -u critical -a Battery \
              -h string:x-canonical-private-synchronous:battery \
              "Battery low" "$cap% remaining"
            break
          fi
        done
      fi
      last=$cap
      sleep 60
    done
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

  systemd.user.services.battery-monitor = {
    Unit = {
      Description = "Notify on low battery thresholds";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      ExecStart = "${batteryMonitor}";
      Restart = "on-failure";
    };
  };

  home.file.".config/waybar/style.css".source = ./waybar/style.css;

  home.packages = [
    volumeControl
    brightnessControl
  ];

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

        network = {
          "format-wifi" = "{icon}";
          "format-ethernet" = "󰈁";
          "format-disconnected" = "󰤮";
          "format-icons" = [
            "󰤯"
            "󰤟"
            "󰤢"
            "󰤥"
            "󰤨"
          ];
          "interval" = 5;
          "tooltip" = false;
        };

        pulseaudio = {
          "format" = "{icon}";
          "format-muted" = "󰝟";
          "format-icons" = {
            "default" = [
              "󰕿"
              "󰖀"
              "󰕾"
            ];
          };
          "on-scroll-up" = "${volumeControl}/bin/volume-notify up";
          "on-scroll-down" = "${volumeControl}/bin/volume-notify down";
          "on-click" = "${volumeControl}/bin/volume-notify mute";
          "on-click-right" = "pavucontrol";
          "tooltip" = false;
        };

        battery = {
          "bat" = "BAT0";
          "format" = "{icon}";
          "format-charging" = "󰂄";
          "format-full" = "󰁹";
          "format-icons" = [
            "󰂎"
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
          "tooltip" = false;
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
