{ lib, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];  

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";

  fonts.fontDir.enable = true;
  fonts.fontconfig.enable = true;
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  programs.niri.enable = true;
  programs.zsh.enable = true;

  programs.wireshark = {
    enable = true;
    dumpcap.enable = true;
  };

  users.users.aleph = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wireshark" ];
  };


  environment.systemPackages = with pkgs; [
    wget
    git
    home-manager
    xwayland-satellite
    hyfetch
    htop
    btop
    waybar
    nixfmt
    direnv
    android-tools
    unzip
    wireshark-qt

    (pkgs.writeShellScriptBin "nix-rebuild" ''
      exec sudo nixos-rebuild switch --flake /home/aleph/nixos-config
    '')

    (pkgs.writeShellScriptBin "nix-reboot" ''
      sudo nixos-rebuild switch --flake /home/aleph/nixos-config && reboot
    '')


  ];

  system.stateVersion = "25.11";
}

