{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:

{
  imports = [
    ../../modules/nixos/backup.nix
  ];

  fonts = {
    fontDir.enable = true;
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      # Phosphor icon font (bold weight), vendored for the waybar icons.
      (stdenvNoCC.mkDerivation {
        pname = "phosphor-icons-font";
        version = "2.1.2";
        src = fetchurl {
          url = "https://raw.githubusercontent.com/phosphor-icons/web/v2.1.2/src/bold/Phosphor-Bold.ttf";
          hash = "sha256-EKChy0+BVqQg+fhM80xOmHHljtLd6h9qgHmtByQ6f7I=";
        };
        dontUnpack = true;
        installPhase = ''
          mkdir -p $out/share/fonts/truetype
          cp $src $out/share/fonts/truetype/Phosphor-Bold.ttf
        '';
      })
    ];
  };

  boot = {
    kernelParams = [
      "init_on_alloc=1"
      "init_on_free=1"
    ];

    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  programs = {
    niri = {
      enable = true;
      package = pkgs.niri;
    };

    ssh = {
      startAgent = false;
      extraConfig = ''
        Host *
          AddKeysToAgent yes
      '';
    };

    steam = {
      enable = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];
    };

    dconf.enable = true;
  };

  services = {
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --cmd niri-session";
          user = "greeter";
        };
      };
    };

    mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
      enableEarlyBootBlocking = true;
    };

    gnome = {
      gcr-ssh-agent.enable = true;
      gnome-keyring.enable = true;
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    udev.packages = [ pkgs.brightnessctl ];
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
    config.common.default = [
      "gnome"
      "gtk"
    ];
  };

  hardware.uinput.enable = true;

  security.pam.services.greetd.enableGnomeKeyring = true;

  users.users.aleph = {
    extraGroups = [
      "video"
      "audio"
      "uinput"
    ];
  };

  environment.systemPackages = with pkgs; [
    brightnessctl
    xwayland-satellite
    waybar
    glib
    libpulseaudio
    libGL
    libx11
    libxext
    libxrender
    libxtst
    libxi
    libxrandr
    protontricks
    bluez
    obsidian
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  systemd.services = {
    mullvad-autoconnect = {
      description = "Enforce Mullvad auto-connect";
      after = [ "mullvad-daemon.service" ];
      requires = [ "mullvad-daemon.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script =
        let
          mullvad = lib.getExe' config.services.mullvad-vpn.package "mullvad";
        in
        ''
          for _ in $(seq 1 30); do
            ${mullvad} status >/dev/null 2>&1 && break
            sleep 1
          done

          ${mullvad} lockdown-mode set on
          ${mullvad} auto-connect set on
          ${mullvad} lan set allow
        '';
    };
  };
}
