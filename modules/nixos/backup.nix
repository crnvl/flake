{
  config,
  inputs,
  pkgs,
  ...
}:

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
      ServerAliveInterval 15
      ServerAliveCountMax 3
  '';

  services.borgbackup.package = inputs.nixpkgs-2311.legacyPackages.${pkgs.system}.borgbackup;

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
    persistentTimer = true;
    failOnWarnings = false;

    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };

    extraCreateArgs = [
      "--stats"
      "--progress"
    ];

    exclude = [
      "pp:/home/aleph/.cache"
      "pp:/home/aleph/.local/share/Trash"

      "pp:/home/aleph/.android/avd"
      "pp:/home/aleph/Android"

      "pp:/home/aleph/.local/share/Steam"
      "pp:/home/aleph/.steam"
      "pp:/home/aleph/.ollama/models"
      "pp:/home/aleph/.BitwigStudio/installed-packages"
      "pp:/home/aleph/.BitwigStudio/cache"
      "pp:/home/aleph/.vscode/extensions"

      "sh:**/.direnv"

      "sh:**/node_modules"
      "sh:**/target"
      "sh:**/__pycache__"
      "sh:**/venv"
      "sh:**/.venv"
      "sh:**/.mypy_cache"
      "sh:**/.pytest_cache"
      "sh:**/.tox"

      "pp:/home/aleph/.cargo/registry"
      "pp:/home/aleph/.cargo/git"
      "pp:/home/aleph/.gradle"
      "pp:/home/aleph/.m2"
      "pp:/home/aleph/.npm"
      "pp:/home/aleph/.pnpm-store"

      "sh:**/*.iso"
      "sh:**/*.qcow2"
      "sh:**/*.vmdk"
    ];

    doInit = true;
  };
}
