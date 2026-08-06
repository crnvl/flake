{ lib, pkgs, mkProxyHost, ... }:

let
  ssoConfig = "/var/lib/jellyfin/plugins/configurations/SSO-Auth.xml";

  ssoLiveTvRbac = pkgs.writeShellScript "jellyfin-sso-livetv-rbac" ''
    set -eu
    [ -e ${ssoConfig} ] || exit 0
    ${lib.getExe pkgs.xmlstarlet} ed -L \
      -d '//LiveTvRoles' \
      -u '//EnableLiveTvRoles' -v true \
      -u '//EnableLiveTv' -v false \
      -s '//EnableLiveTvRoles/..' -t elem -n LiveTvRoles -v "" \
      -s '//LiveTvRoles' -t elem -n string -v livetv \
      ${ssoConfig}
  '';
in
{
  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  users.users.jellyfin.extraGroups = [ "media" ];

  systemd.services.jellyfin.serviceConfig.ExecStartPre = [ "${ssoLiveTvRbac}" ];

  services.nginx.virtualHosts."jellyfin.shimme.rs" = mkProxyHost {
    port = 8096;
    locationExtraConfig = "proxy_set_header X-Forwarded-Proto https;";
  };
}
