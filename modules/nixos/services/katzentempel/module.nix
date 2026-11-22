{ config, lib, pkgs, ... }:
let
  cfg = config.services.katzentempelProxy;
  python = pkgs.python3.withPackages (ps: [ ps.flask ps.requests ps.gunicorn ]);
  source = pkgs.runCommand "katzentempel-proxy-src" { } ''
    mkdir -p $out
    cp ${./server.py} $out/server.py
  '';
in {
  options.services.katzentempelProxy = {
    enable = lib.mkEnableOption "the Katzentempel forwarding proxy";
    listenHost = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
    listenPort = lib.mkOption { type = lib.types.port; default = 3083; };
    originalHost = lib.mkOption { type = lib.types.str; default = "https://api.helloagain.at"; };
  };
  config = lib.mkIf cfg.enable {
    systemd.services.katzentempel-proxy = {
      description = "Katzentempel forwarding-only API proxy";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        ORIGINAL_HOST = cfg.originalHost;
        TRUST_PROXY = "1";
      };
      serviceConfig = {
        ExecStart = "${python}/bin/gunicorn --no-control-socket --chdir ${source} --bind ${cfg.listenHost}:${toString cfg.listenPort} --workers 2 --threads 4 --timeout 90 server:app";
        DynamicUser = true;
        Restart = "on-failure";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };
  };
}
