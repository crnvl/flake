{ pkgs, ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  virtualisation.libvirtd.enable = true;
  boot.kernelModules = [
    "kvm-amd"
    "kvm-intel"
  ];

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

  programs.nix-ld.enable = true;

  users.users.aleph = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wireshark"
      "qemu-libvirtd"
      "libvirtd"
      "wheel"
      "video"
      "audio"
      "disk"
      "networkmanager"
    ];
  };

  environment.systemPackages = with pkgs; [
    tree
    wget
    git
    xwayland-satellite
    hyfetch
    htop
    btop
    waybar
    nixfmt
    direnv
    android-tools
    unzip
    wireshark
    file
    stdenv.cc.cc
    zlib
    openssl
    glib
    libpulseaudio
    libGL
    libx11
    libxext
    libxrender
    libxtst
    libxi
    libxrandr

    (pkgs.writeShellScriptBin "nix-rebuild" ''
      exec sudo nixos-rebuild switch --flake /home/aleph/nixos-config
    '')

    (pkgs.writeShellScriptBin "nix-reboot" ''
      sudo nixos-rebuild switch --flake /home/aleph/nixos-config && reboot
    '')

  ];

  system.stateVersion = "25.11";
}
