{ config, ... }:

{
  # Contains LIDARR__AUTH__APIKEY=... so the API key is pinned declaratively
  # and can be shared with soularr (soularr-env) without copying it out of
  # the UI.
  age.secrets.lidarr-env.file = ../../../../hosts/shimmers/secrets/lidarr-env.age;

  services.lidarr = {
    enable = true;
    openFirewall = false;
    environmentFiles = [ config.age.secrets.lidarr-env.path ];
  };

  systemd.services.lidarr = {
    vpnConfinement = {
      enable = true;
      vpnNamespace = "wg";
    };
    unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];
  };

  # media: /mnt/chroma library, sabnzbd/qbittorrent downloads, and the slskd
  # downloads dir (setgid media, see slskd.nix) so imports can move files out.
  # sabnzbd: its job dirs are created sabnzbd:sabnzbd, so moving finished
  # downloads out needs that group (same as sonarr and radarr).
  users.users.lidarr.extraGroups = [
    "media"
    "sabnzbd"
  ];

  my.vpn.portMappings = [
    {
      from = 8686;
      to = 8686;
    }
  ];
}
