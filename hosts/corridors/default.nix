{ inputs, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # Webcam -> Jellyfin Live TV; disabled for now, re-enable together with
    # webcam-livetv.nix on shimmers.
    # ./webcam.nix
    ../../modules/nixos/server.nix

    # Secure Boot (needed for Vanguard/League in the Windows dual-boot).
    # Keys live in /var/lib/sbctl; Windows stays bootable via enrolled
    # Microsoft keys (sbctl enroll-keys --microsoft).
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  # lanzaboote replaces systemd-boot (it embeds a signed systemd-boot).
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
  environment.systemPackages = [ pkgs.sbctl ];

  system.stateVersion = "25.11";

  networking = {
    hostName = "corridors";
    networkmanager.enable = true;

    firewall = {
      allowedTCPPorts = [
        27036
        27037
      ];
      allowedUDPPorts = [
        27031
        27036
      ];
    };
  };

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /mnt/storage1 0755 aleph users -"
    "d /mnt/storage2 0755 aleph users -"
  ];

  services = {
    mullvad-vpn.enable = false;

    # Sink preference: UMC202HD interface when plugged in, otherwise the TV on
    # the Radeon's HDMI. The DualShock 4 exposes a USB headset jack that
    # outranks HDMI by default, so plugging the controller in silently steals
    # the default sink; push it to the bottom.
    pipewire.wireplumber.extraConfig."51-corridors-sinks" = {
      "monitor.alsa.rules" = [
        {
          matches = [ { "node.name" = "~alsa_output.usb-BEHRINGER_UMC202HD_192k.*"; } ];
          actions.update-props = {
            "priority.session" = 3000;
            "priority.driver" = 3000;
          };
        }
        {
          matches = [ { "node.name" = "~alsa_output.pci-0000_01_00.1.hdmi.*"; } ];
          actions.update-props = {
            "priority.session" = 2000;
            "priority.driver" = 2000;
          };
        }
        {
          matches = [ { "node.name" = "~alsa_output.usb-Sony_Interactive_Entertainment_Wireless_Controller.*"; } ];
          actions.update-props = {
            "priority.session" = 100;
            "priority.driver" = 100;
          };
        }
      ];
    };

    wivrn = {
      enable = true;
      openFirewall = true;
      autoStart = true;

      steam.enable = true;
      steam.importOXRRuntimes = true;
    };
  };
}
