{
  config,
  pkgs,
  lib,
  ...
}:

let
  rustdesk = import ../../../rustdesk.nix;
  hostName = config.networking.hostName;
  secretName = "rustdesk-password";
in
{
  age.secrets.${secretName} = {
    file = ../../../hosts/${hostName}/secrets/${secretName}.age;
    mode = "0400";
    owner = "aleph";
  };

  age.identityPaths = [ "/etc/age/host.key" ];

  environment.systemPackages = [ pkgs.rustdesk ];

  systemd.user.services.rustdesk = {
    description = "RustDesk unattended remote desktop client";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];

    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };

    script = ''
      ${lib.optionalString (rustdesk.configString != "") ''
        ${pkgs.rustdesk}/bin/rustdesk --config ${lib.escapeShellArg rustdesk.configString}
      ''}
      ${pkgs.rustdesk}/bin/rustdesk --password "$(cat ${config.age.secrets.${secretName}.path})"
      exec ${pkgs.rustdesk}/bin/rustdesk
    '';
  };
}
