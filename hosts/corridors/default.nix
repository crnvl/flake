{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  system.stateVersion = "25.11";

  networking = {
    hostName = "corridors";
    networkmanager.enable = true;
  };

  programs.steam = {
    enable = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
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
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --cmd niri-session";
          user = "greeter";
        };
      };
    };

    wivrn = {
      enable = true;
      openFirewall = true;
      defaultRuntime = true;
      autoStart = true;
    };
  };
}
