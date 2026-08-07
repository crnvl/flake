{ pkgs, mkProxyHost, ... }:

let
  ssoConfig = "/var/lib/jellyfin/plugins/configurations/SSO-Auth.xml";

  liveTvGroup = "jellyfin_users@id.shimme.rs";

  cfg = "//*[Roles/string='${liveTvGroup}']";

  ssoLiveTvRbac = pkgs.writeShellScript "jellyfin-sso-livetv-rbac" ''
    set -eu
    [ -e ${ssoConfig} ] || exit 0
    ${pkgs.xmlstarlet}/bin/xmlstarlet ed -L \
      -d "${cfg}/LiveTvRoles" \
      -u "${cfg}/EnableLiveTvRoles" -v true \
      -u "${cfg}/EnableLiveTv" -v false \
      -s "${cfg}" -t elem -n LiveTvRoles -v "" \
      -s "${cfg}/LiveTvRoles" -t elem -n string -v '${liveTvGroup}' \
      ${ssoConfig}
  '';
in
{
  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  users.users.jellyfin.extraGroups = [ "media" ];

  systemd.services.jellyfin = {
    serviceConfig.ExecStartPre = [ "${ssoLiveTvRbac}" ];
    environment.TZ = "Europe/Berlin";
  };

  services.nginx.virtualHosts."jellyfin.shimme.rs" = mkProxyHost {
    port = 8096;
    locationExtraConfig = "proxy_set_header X-Forwarded-Proto https;";
  };
}
