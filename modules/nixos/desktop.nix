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

  nixpkgs.overlays = [
    (final: prev: {
      # Vesktop's arRPC bundles a snapshot of Discord's detectable games list
      # that only knows Deadlock by its old project8.exe binary, so the game
      # never shows up as an activity. Add the current deadlock.exe name; jq
      # leaves the list alone once a newer snapshot already has it.
      vesktop = prev.vesktop.overrideAttrs (old: {
        preBuild = (old.preBuild or "") + ''
          db=node_modules/arrpc/src/process/detectable.json
          jq -e 'any(.[]; .id == "1276737795012165766")' "$db" >/dev/null
          jq '(.[] | select(.id == "1276737795012165766" and (.executables | all(.name != "win64/deadlock.exe"))) | .executables)
            += [{ is_launcher: false, name: "win64/deadlock.exe", os: "win32" }]' "$db" > detectable.json
          mv detectable.json "$db"
        '';
      });
    })
  ];

  programs = {
    niri = {
      enable = true;
      package = pkgs.niri;
    };

    ssh = {
      startAgent = false;
      # The proxyagain flake input is fetched via the "git-gay-proxyagain" host
      # alias (see flake.nix). shimmers binds it to a scoped deploy key; on
      # desktops just resolve it to git.gay and use the user's own key, which
      # is already authorized for the repo. Without this, `nix flake update`
      # (or any fetch not already in the store) fails with an unresolvable
      # hostname.
      extraConfig = ''
        Host *
          AddKeysToAgent yes

        Host git-gay-proxyagain
          HostName git.gay
          User git
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
      # mkDefault so individual hosts (e.g. corridors) can opt out.
      enable = lib.mkDefault true;
      enableEarlyBootBlocking = true;
      gui.enable = true;
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

    udev = {
      packages = [ pkgs.brightnessctl ];
      # Nintendo Switch in RCM mode (APX) - allow payload injection without root
      extraRules = ''
        SUBSYSTEM=="usb", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7321", MODE="0660", TAG+="uaccess"
      '';
    };
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
    config.common = {
      default = [
        "gnome"
        "gtk"
      ];
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    };
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
    fusee-nano
    obsidian
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    rar
  ];

  systemd.services = lib.mkIf config.services.mullvad-vpn.enable {
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
