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

  services.borgbackup.package =
    inputs.nixpkgs-2311.legacyPackages.${pkgs.stdenv.hostPlatform.system}.borgbackup;

  services.borgbackup.jobs.home = {
    paths = [ "/home/aleph" ];
    repo = "ssh://u615907@u615907.your-storagebox.de:23/./backups/${config.networking.hostName}";

    environment.BORG_RSH = "ssh -i /home/aleph/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ProxyCommand='ssh -i /home/aleph/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new -W u615907.your-storagebox.de:23 aleph@shimme.rs'";

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

  systemd.services.borgbackup-check-home = {
    description = "BorgBackup integrity check (home repo)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      config.services.borgbackup.package
      pkgs.openssh
    ];
    environment = {
      BORG_REPO = config.services.borgbackup.jobs.home.repo;
      BORG_PASSCOMMAND = config.services.borgbackup.jobs.home.encryption.passCommand;
      BORG_RSH = config.services.borgbackup.jobs.home.environment.BORG_RSH;
    };
    serviceConfig = {
      Type = "oneshot";
      # Stay out of the way of foreground work.
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
    };
    script = ''
      # Persistent catch-up can fire at boot before DNS is ready.
      for _ in $(seq 1 30); do
        ${pkgs.glibc.bin}/bin/getent hosts shimme.rs >/dev/null 2>&1 && break
        sleep 2
      done

      if (( 10#$(date +%d) <= 7 )); then
        echo "First week of the month -> full --verify-data (slow, reads every chunk)"
        exec borg check --verbose --verify-data
      else
        echo "Routine --repository-only structure check"
        exec borg check --verbose --repository-only
      fi
    '';
  };

  systemd.timers.borgbackup-check-home = {
    description = "Weekly BorgBackup integrity check (home repo)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 05:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
