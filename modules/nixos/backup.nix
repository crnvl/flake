{ config, ... }:

{
  systemd.tmpfiles.rules = [ "d /root/.ssh 0700 root root -" ];

  programs.ssh.extraConfig = ''
    Host backup-box
      HostName u615907.your-storagebox.de
      User u615907
      Port 23
      ProxyCommand ssh -i /home/aleph/.ssh/id_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -W %h:%p aleph@shimme.rs
      IdentityFile /home/aleph/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
      BatchMode yes
  '';

  services.restic.backups.home = {
    initialize = true;
    repository = "sftp:backup-box:/backups/${config.networking.hostName}";
    passwordFile = "/etc/restic-home-password";

    paths = [ "/home/aleph" ];

    extraBackupArgs = [
      "--exclude=/home/aleph/.cache"
      "--exclude=/home/aleph/.android/avd"
      "--exclude=/home/aleph/Android"
      "--exclude=/home/aleph/.local/share/Steam"
      "--exclude=/home/aleph/.vagrant.d/boxes"
      "--exclude=/home/aleph/.gradle"
      "--exclude=**/node_modules"
      "--exclude=**/target"
      "--exclude=**/__pycache__"
    ];

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
  };
}
