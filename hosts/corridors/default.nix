{ ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  system.stateVersion = "25.11";

  networking = {
    hostName = "corridors";
    networkmanager.enable = true;
  };

  hardware.graphics.enable = true;

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "niri-session";
        user = "aleph";
      };
    };
  };

  services.xserver.videoDrivers = [ "modesetting" ];
}
