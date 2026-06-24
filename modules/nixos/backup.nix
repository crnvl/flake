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

  services.borgbackup.jobs.home = {
    paths = [ "/home/aleph" ];
    repo = "ssh://u615907@u615907.your-storagebox.de:23/./backups/${config.networking.hostName}";

    environment.BORG_RSH = "ssh -i /home/aleph/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ProxyCommand='ssh -i /home/aleph/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new -W %%h:%%p aleph@shimme.rs'";

    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat /etc/borg-passphrase";
    };

    compression = "auto,zstd";
    startAt = "daily";

    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };

    exclude = [
      "pp:/home/aleph/.cache"
      "pp:/home/aleph/.android/avd"
      "pp:/home/aleph/Android"
      "pp:/home/aleph/.local/share/Steam"
      "pp:/home/aleph/.vagrant.d/boxes"
      "pp:/home/aleph/.gradle"
      "sh:**/node_modules"
      "sh:**/target"
      "sh:**/__pycache__"
    ];

    doInit = true;
  };
}
