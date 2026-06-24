{ pkgs, ... }:

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
      exec sudo nixos-rebuild switch --flake /home/aleph/flake
    '')

    (pkgs.writeShellScriptBin "nix-update" ''
      cd /home/aleph/flake && git pull && exec sudo nixos-rebuild switch --flake .
    '')

    (pkgs.writeShellScriptBin "nix-reboot" ''
      sudo nixos-rebuild switch --flake /home/aleph/flake && reboot
    '')

    (writeShellScriptBin "android-emulator" ''
      exec ${steam-run}/bin/steam-run \
        /home/aleph/Android/Sdk/emulator/emulator "$@" -gpu host
    '')
  ];
}
