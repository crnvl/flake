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
      substituters = [ "https://helium-nix.cachix.org" ];
      trusted-public-keys = [
        "helium-nix.cachix.org-1:a8YPjt9O4GPyX0u3gjg/aWpb14teU9aRiSG/MOaSFgw="
      ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
    };
  };

  system.activationScripts.cleanupGenerations = ''
    ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +5
  '';

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
