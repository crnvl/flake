{ lib, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];  

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    wget
    git
    home-manager
  ];

  system.stateVersion = "25.11";
}

