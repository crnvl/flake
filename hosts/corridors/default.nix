{ ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

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
    wivrn = {
      enable = true;
      openFirewall = true;
      autoStart = true;

      steam.enable = true;
      steam.importOXRRuntimes = true;
    };
  };
}
