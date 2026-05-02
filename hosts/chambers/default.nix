{ ... }:

{
  imports = [
    ./hardware-configuration.nix
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
          command = "niri-session";
          user = "aleph";
        };
      };
    };

    xserver.videoDrivers = [ "modesetting" ];
  };
}
