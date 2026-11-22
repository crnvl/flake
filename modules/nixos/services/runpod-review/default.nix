{
  config,
  lib,
  pkgs,
  ...
}:

let
  name = "runpod-review";
  domain = "review-weights.shimme.rs";
  python = pkgs.python3.withPackages (p: [
    p.aiohttp
    p.httpx
  ]);
  worker = "${python}/bin/python3 ${./.}/gateway.py";
  # An operator can use a root-only runtime file or add the usual encrypted secret.
  secret = ../../../../hosts/shimmers/secrets/runpod-review-key.age;
  keyFile =
    if builtins.pathExists secret then
      config.age.secrets.runpod-review-key.path
    else
      "/etc/runpod-review/api-key";
  unit = {
    User = name;
    Group = name;
    StateDirectory = name;
    StateDirectoryMode = "0700";
    UMask = "0077";
    LoadCredential = "runpod-key:${keyFile}";
    ProtectSystem = "strict";
    ProtectHome = true;
    NoNewPrivileges = true;
    PrivateTmp = true;
    PrivateDevices = true;
    CapabilityBoundingSet = "";
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
  };
  weights = builtins.fromJSON (builtins.readFile ./model.json);
  file = weights.file;
  dir = "/var/lib/runpod-review-weights";
  rev = weights.revision;
  sha = weights.sha256;
in
{
  age.secrets = lib.optionalAttrs (builtins.pathExists secret) { runpod-review-key.file = secret; };
  users.groups.${name}.members = [ "aleph" ]; # SSH forwarding to the paid inference socket
  users.users.${name} = {
    isSystemUser = true;
    group = name;
  };
  users.groups.runpod-review-fetch = { };
  users.users.runpod-review-fetch = {
    isSystemUser = true;
    group = "runpod-review-fetch";
  };

  # Explicit one-off preparation; no weight download or paid allocation during a rebuild.
  systemd.services.runpod-review-weights = {
    description = "Cache pinned Qwen3.8 Aggressive weights on Hetzner";
    path = [
      pkgs.coreutils
      pkgs.curl
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "runpod-review-fetch";
      Group = "runpod-review-fetch";
      StateDirectory = "runpod-review-weights";
      StateDirectoryMode = "0755";
      UMask = "0077";
      ProtectSystem = "strict";
      NoNewPrivileges = true;
      Nice = 15;
    };
    script = ''
      cd ${dir}
      if test -f ${file} && echo '${sha}  ${file}' | sha256sum --status -c; then exit 0; fi
      curl -fLsS --retry 3 -C - -o ${file}.part \
        'https://huggingface.co/${weights.repo}/resolve/${rev}/${file}'
      if ! echo '${sha}  ${file}.part' | sha256sum -c; then rm -f ${file}.part; exit 1; fi
      chmod 0444 ${file}.part
      mv -f ${file}.part ${file}
    '';
  };

  systemd.services.${name} = {
    description = "On-demand Qwen3.8 Aggressive reviewer (no allocation at boot)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    unitConfig.ConditionPathExists = keyFile;
    serviceConfig = unit // {
      RuntimeDirectory = name;
      RuntimeDirectoryMode = "0750";
      ExecStart = "${worker} serve";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  systemd.services.runpod-review-reap = {
    description = "Release idle, expired or abandoned reviewer Pod";
    unitConfig.ConditionPathExists = keyFile;
    serviceConfig = unit // {
      Type = "oneshot";
      ExecStart = "${worker} reap";
    };
  };
  systemd.timers.runpod-review-reap = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15s";
      OnUnitActiveSec = "30s";
      AccuracySec = "2s";
    };
  };
  systemd.services.runpod-review-release = {
    description = "Immediately terminate the current shimmers review Pod";
    unitConfig.ConditionPathExists = keyFile;
    serviceConfig = unit // {
      Type = "oneshot";
      ExecStart = "${worker} release";
    };
  };
  systemd.services.runpod-review-pause = {
    description = "Pause GPU allocations and immediately release the current Pod";
    unitConfig.ConditionPathExists = keyFile;
    serviceConfig = unit // {
      Type = "oneshot";
      ExecStart = "${worker} pause";
    };
  };
  systemd.services.runpod-review-resume = {
    description = "Permit GPU review requests (does not allocate a Pod)";
    unitConfig.ConditionPathExists = keyFile;
    serviceConfig = unit // {
      Type = "oneshot";
      ExecStart = "${worker} resume";
    };
  };
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "runpod-review-status" "exec ${worker} status")
  ];

  # Only the pinned weights are downloadable; the credential is lease-specific and
  # is never embedded in the URL. No public chat, filesystem listing or control API.
  services.nginx.virtualHosts.${domain} = {
    enableACME = true;
    forceSSL = true;
    extraConfig = "access_log off;";
    locations."/".return = "404";
    locations."= /model.gguf".proxyPass = "http://127.0.0.1:18092";
    locations."= /_private/model.gguf" = {
      alias = "${dir}/${file}";
      extraConfig = ''
        internal;
        default_type application/octet-stream;
        add_header Cache-Control "private, no-store" always;
      '';
    };
  };
}
