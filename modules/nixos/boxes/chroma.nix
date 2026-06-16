{ config, pkgs, ... }:

{
  age.secrets.chroma-smb.file = ../../../hosts/shimmers/secrets/chroma-smb.age;

  environment.systemPackages = [ pkgs.cifs-utils ];

  fileSystems."/mnt/chroma" = {
    device = "//u615907.your-storagebox.de/backup";
    fsType = "cifs";
    options = [
      "credentials=${config.age.secrets.chroma-smb.path}"
      "seal"
      "uid=jellyfin"
      "gid=media"
      "file_mode=0664"
      "dir_mode=0775"
      "nounix"
      "iocharset=utf8"
      "vers=3.0"
      "cache=loose"
      "nofail"
      "_netdev"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.mount-timeout=15s"
    ];
  };
}
