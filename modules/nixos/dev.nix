{ pkgs, ... }:

{
  virtualisation.libvirtd.enable = true;
  boot.kernelModules = [
    "kvm-amd"
    "kvm-intel"
  ];

  programs = {
    wireshark = {
      enable = true;
      dumpcap.enable = true;
    };

    nix-ld.enable = true;
  };

  users.users.aleph = {
    extraGroups = [
      "qemu-libvirtd"
      "libvirtd"
      "disk"
    ];
  };

  environment.systemPackages = with pkgs; [
    android-tools
    stdenv.cc.cc
    openssl
    zlib
    nixd
    nil
  ];
}
