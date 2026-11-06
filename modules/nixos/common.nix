{ pkgs, ... }:

let
  flakePath = "/home/aleph/flake";
in
{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 5;
  };


  nixpkgs.config.allowUnfree = true;
  nix.settings.use-xdg-base-directories = true;

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.aleph = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };

  environment.systemPackages = with pkgs; [
    tree
    wget
    git
    hyfetch
    htop
    btop
    dig
    unzip
    file
    nixfmt
    direnv
    steam-run

    (pkgs.writeShellScriptBin "nix-rebuild" ''
      exec sudo nixos-rebuild switch --flake ${flakePath}
    '')

    (pkgs.writeShellScriptBin "nix-update" ''
      cd ${flakePath} && git pull && exec sudo nixos-rebuild switch --flake .
    '')

    (pkgs.writeShellScriptBin "nix-reboot" ''
      sudo nixos-rebuild switch --flake ${flakePath} && reboot
    '')

    (writeShellScriptBin "android-emulator" ''
      exec ${steam-run}/bin/steam-run \
        /home/aleph/Android/Sdk/emulator/emulator "$@" -gpu host
    '')
  ];
}
