{ lib, pkgs, ... }:

{
  services = {
    pipewire = {
      jack.enable = true;

      extraConfig.pipewire."92-audio" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.allowed-rates" = [
            44100
            48000
          ];
          "default.clock.quantum" = 1024;
          "default.clock.min-quantum" = 32;
          "default.clock.max-quantum" = 2048;
        };
      };
    };

    udisks2.enable = true;
  };

  security = {
    rtkit.enable = true;

    pam.loginLimits = [
      {
        domain = "@audio";
        item = "memlock";
        type = "-";
        value = "unlimited";
      }
      {
        domain = "@audio";
        item = "rtprio";
        type = "-";
        value = "99";
      }
      {
        domain = "@audio";
        item = "nofile";
        type = "soft";
        value = "99999";
      }
      {
        domain = "@audio";
        item = "nofile";
        type = "hard";
        value = "99999";
      }
    ];
  };

  boot = {
    kernelParams = [ "threadirqs" ];

    kernelModules = [
      "snd-seq"
      "snd-rawmidi"
    ];

    kernel.sysctl."vm.max_map_count" = 1048576;
  };

  hardware.graphics.enable32Bit = lib.mkDefault true;

  environment.etc."udisks2/mount_options.conf".text = ''
    [defaults]
    udf_allow=uid=$UID,gid=$GID,iocharset,utf8,umask,mode,dmode,unhide,undelete
  '';

  environment.systemPackages = with pkgs; [
    p7zip
    pciutils
    qpwgraph
    samba

    (writeShellScriptBin "music-mode" ''
      set -eu

      pwm="${pipewire}/bin/pw-metadata"

      case "''${1:-}" in
        on)
          quantum="''${2:-256}"
          "$pwm" -n settings 0 clock.force-quantum "$quantum" >/dev/null
          echo "music-mode: quantum forced to $quantum"
          ;;
        off)
          "$pwm" -n settings 0 clock.force-quantum 0 >/dev/null
          echo "music-mode: quantum released"
          ;;
        status)
          "$pwm" -n settings | grep -E "clock\.(force-)?quantum|clock\.rate" || true
          ;;
        *)
          echo "usage: music-mode {on [quantum] | off | status}" >&2
          exit 1
          ;;
      esac
    '')
  ];
}
