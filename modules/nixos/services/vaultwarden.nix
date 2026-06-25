{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  domain = "vault.shimme.rs";
  backupDir = "/var/backup/vaultwarden";
in
{
  age.secrets.vaultwarden-env.file = ../../../hosts/shimmers/secrets/vaultwarden-env.age;
  age.secrets.vaultwarden-borg-passphrase.file = ../../../hosts/shimmers/secrets/vaultwarden-borg-passphrase.age;

  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";

    environmentFile = config.age.secrets.vaultwarden-env.path;

    backupDir = backupDir;

    configureNginx = true;
    domain = domain;

    config = {
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = true;
      PASSWORD_HINTS_ALLOWED = false;
      SHOW_PASSWORD_HINT = false;
      ROCKET_LOG = "critical";
    };
  };

  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    extraConfig = "client_max_body_size 525M;";
  };

  systemd.timers.backup-vaultwarden.timerConfig.OnCalendar = lib.mkForce "*-*-* 04:00:00";

  services.borgbackup.package =
    inputs.nixpkgs-2311.legacyPackages.${pkgs.stdenv.hostPlatform.system}.borgbackup;

  services.borgbackup.jobs.vaultwarden = {
    paths = [ backupDir ];
    repo = "ssh://u615907@u615907.your-storagebox.de:23/./backups/vaultwarden";
    doInit = true;

    environment.BORG_RSH = "ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new -o BatchMode=yes";

    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat ${config.age.secrets.vaultwarden-borg-passphrase.path}";
    };

    compression = "auto,zstd";
    startAt = "*-*-* 04:15:00";
    persistentTimer = true;

    prune.keep = {
      daily = 14;
      weekly = 8;
      monthly = 12;
    };

    extraCreateArgs = [ "--stats" ];
  };
}
