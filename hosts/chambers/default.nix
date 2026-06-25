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

    logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandlePowerKey = "suspend-then-hibernate";
    };

    xserver.videoDrivers = [ "modesetting" ];
  };

  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";
}
