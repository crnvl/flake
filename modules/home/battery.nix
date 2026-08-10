{ pkgs, lib, ... }:

# Low-battery warnings.
#
# Split out of the old waybar.nix, which is where this lived only because the
# notification it fires used to be rendered by waybar's notification ticker.
# It has nothing to do with the bar, so it stands on its own now.
#
# The notify-send call lands in Quickshell's notification daemon
# (modules/home/quickshell/Notifications.qml). `-u critical` is what makes it
# render with the double-line frame and skip the expiry timeout -- in a
# monochrome palette that framing is the only way urgency can show itself.
#
# The x-canonical-private-synchronous hint collapses repeat warnings into one
# notification rather than stacking 25/10/5 on top of each other.
let
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
}
