{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "cats";

  networking.networkmanager.enable = true;

  services.xserver.enable = true;

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "niri-session";
        user = "aleph";
      };
    };
  };

  hardware.graphics.enable = true;

  services.mullvad-vpn.enable = true;
  services.mullvad-vpn.package = pkgs.mullvad-vpn;

  # Intel/AMD
  services.xserver.videoDrivers = [ "modesetting" ];
}
