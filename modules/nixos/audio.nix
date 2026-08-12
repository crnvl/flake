{ lib, pkgs, ... }:

{
  services = {
    pipewire = {
      jack.enable = true;

      # A wide quantum range lets clients negotiate down on demand. The default
      # sits high deliberately: with no audio interface and no MIDI controller
      # there is nothing to monitor in real time, so throughput and stability
      # are worth more than latency. Use `music-mode on` to force it lower.
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

    # Native Instruments ships sample libraries as UDF images whose installers
    # live in hidden files. udisks refuses the `unhide` mount option unless it
    # is allowlisted in mount_options.conf below.
    udisks2.enable = true;
  };

  security = {
    rtkit.enable = true;

    # The pipewire module grants @pipewire its own limits, but Wine and the
    # plugins it hosts need these granted to @audio explicitly.
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

    # Wine maps each plugin binary separately. The 65530 default is exhausted
    # well before a few hundred plugins are loaded, and it surfaces as opaque
    # crashes rather than an obvious resource error.
    #
    # vm.swappiness is deliberately left alone: the usual audio advice to lower
    # it assumes swapping to disk, but zram makes swap compressed RAM. memlock
    # above already protects the realtime path.
    kernel.sysctl."vm.max_map_count" = 1048576;
  };

  # corridors sets this explicitly. Two unqualified bool definitions of one
  # option are a module conflict, not a merge, so this has to defer.
  hardware.graphics.enable32Bit = lib.mkDefault true;

  environment.etc."udisks2/mount_options.conf".text = ''
    [defaults]
    udf_allow=uid=$UID,gid=$GID,iocharset,utf8,umask,mode,dmode,unhide,undelete
  '';

  environment.systemPackages = with pkgs; [
    p7zip
    pciutils
    qpwgraph
    samba # NI installers shell out to ntlm_auth

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
