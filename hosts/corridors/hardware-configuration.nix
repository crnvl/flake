{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "ahci"
        "usb_storage"
        "usbhid"
        "sd_mod"
        "sr_mod"
      ];
      kernelModules = [ ];
    };

    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/8b128acd-261d-4b41-9ee1-dc7437ddbcd1";
      fsType = "ext4";
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/DD14-D330";
      fsType = "vfat";
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };

    "/mnt/storage1" = {
      device = "/dev/disk/by-uuid/39dc6076-8b89-46f2-af13-89d6fcdb6740";
      fsType = "ext4";
      options = [ "nofail" ];
    };

    "/mnt/storage2" = {
      # by-partuuid, not by-uuid: the Windows MSR partition (sdc1) carries a
      # stale ext4 superblock with the same fs UUID, so by-uuid can resolve
      # to the 16M MSR and the mount fails.
      device = "/dev/disk/by-partuuid/e9e319ec-9b47-4b32-826e-fb66b99b95f2";
      fsType = "ext4";
      options = [ "nofail" ];
    };
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
