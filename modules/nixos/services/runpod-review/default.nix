{
  config,
  lib,
  pkgs,
  ...
}:

let
  name = "runpod-review";
  domain = "review-weights.shimme.rs";
  package = pkgs.rustPlatform.buildRustPackage {
    pname = "runpod-gateway";
    version = "0.1.0";
    src = lib.cleanSource ./.;
    cargoLock.lockFile = ./Cargo.lock;
    # Unit tests use local HTTP stand-ins, not Runpod or real credentials.
    doCheck = true;
  };
  worker = "${package}/bin/runpod-gateway";
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
  dir = "/var/lib/llm/models";
  sha = weights.sha256;
in
{
  age.secrets = lib.optionalAttrs (builtins.pathExists secret) { runpod-review-key.file = secret; };
  users.groups.${name}.members = [ "aleph" ]; # SSH forwarding to the paid inference socket
  users.users.${name} = {
    isSystemUser = true;
    group = name;
  };

  # Explicit one-off preparation; no weight download or paid allocation during a rebuild.
  systemd.services.runpod-review-weights = {
    description = "Verify the existing Qwen3.6 GGUF for GPU inference";
    wants = [ "llm-model-fetch.service" ];
    after = [ "llm-model-fetch.service" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      User = name;
      Group = name;
      UMask = "0077";
      ProtectSystem = "strict";
      NoNewPrivileges = true;
      Nice = 15;
    };
    script = ''
      cd ${dir}
      echo '${sha}  ${file}' | sha256sum -c
    '';
  };

  systemd.services.${name} = {
    description = "Qwen3.6 GPU inference gateway (Rust; no allocation at boot)";
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
