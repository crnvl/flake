{ ... }:

{
  nixpkgs.hostPlatform = "x86_64-linux";
  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content.type = "gpt";
    content.partitions.boot = {
      size = "512M";
      type = "EF00";
      content = {
        type = "filesystem";
        format = "vfat";
        mountpoint = "/boot";
      };
    };
    content.partitions.root = {
      size = "100%";
      content = {
        type = "filesystem";
        format = "ext4";
        mountpoint = "/";
      };
    };
  };
}
