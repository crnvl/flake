{ ... }:
{

  programs.waybar = {
    enable = true;
    settings = [
      {
        layer = "top";
        style = "~/.config/waybar/style.css";
        position = "bottom";
        spacing = 0;
        height = 0;

        margin-top = 0;
        margin-right = 0;
        margin-bottom = 0;
        margin-left = 0;

        modules-left = [
          "custom/grrr"
          "niri/workspaces"
          "tray"
          "custom/notification"
        ];

        modules-center = [
          "clock#secondary"
          "clock"
          "custom/weather"
        ];

        modules-right = [
          "cpu"
          "custom/temp"
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
          "tooltip" = false;
          "format" = "{icon}";
          "format-icons" = {
            "notification" = "<span foreground='#d65d0e'><sup></sup></span>";
            "none" = "";
            "dnd-notification" = "󰂛<span foreground='#d65d0e'><sup></sup></span>";
            "dnd-none" = "󰂛";
            "inhibited-notification" = "<span foreground='#d65d0e'><sup></sup></span>";
            "inhibited-none" = "";
            "dnd-inhibited-notification" = "󰂛<span foreground='#d65d0e'><sup></sup></span>";
            "dnd-inhibited-none" = "󰂛";
          };
          "return-type" = "json";
          "exec-if" = "which swaync-client";
          "exec" = "swaync-client -swb";
          "on-click" = "swaync-client -t -sw";
          "on-click-right" = "swaync-client -d -sw";
          "escape" = true;
        };

        "custom/grrr" = {
          "exec" = "bash print_grrr.sh";
        };

        "custom/weather" = {
          "exec" = "curl -s 'wttr.in/Bielefeld?format=1'";
          "interval" = 600;
        };
      }
    ];
  };
}
