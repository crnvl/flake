{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
  ];

  system.stateVersion = "25.11";

  networking = {
    hostName = "chambers";
    networkmanager.enable = true;
  };

  hardware.graphics.enable = true;

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

    logind = {
      lidSwitch = "suspend-then-hibernate";
      powerKey = "suspend-then-hibernate";
    };

    xserver.videoDrivers = [ "modesetting" ];
  };

  systemd.sleep.extraConfig = ''
    HibernateDelaySec=30min
  '';
}
