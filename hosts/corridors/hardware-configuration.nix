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
    };

    "/mnt/storage2" = {
      device = "/dev/disk/by-uuid/a149898d-99d8-4d56-983a-abce9a48ce81";
      fsType = "ext4";
    };
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
