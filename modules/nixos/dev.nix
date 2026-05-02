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
      "wireshark"
      "qemu-libvirtd"
      "libvirtd"
      "disk"
    ];
  };

  environment.systemPackages = with pkgs; [
    android-tools
    wireshark
    stdenv.cc.cc
    zlib
    openssl
  ];
}
