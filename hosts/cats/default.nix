{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  system.stateVersion = "25.11";

  networking = {
    hostName = "cats";
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

    mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };

    xserver.videoDrivers = [ "modesetting" ];
  };
}
