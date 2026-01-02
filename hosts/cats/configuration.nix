{ config, lib, pkgs, ... }:

{
  imports = [
      ./hardware-configuration.nix
  ];
  
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "cats";

  networking.networkmanager.enable = true;

  services.xserver.enable = true;
  
  # Niri
  #  programs.niri.enable = true;

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

  # Intel/AMD
  services.xserver.videoDrivers = [ "modesetting" ];

  users.users.aleph = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    packages = with pkgs; [
      tree
    ];
  };
}

