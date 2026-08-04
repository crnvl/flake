{ ... }:

{
  services.qbittorrent = {
    enable = true;
    group = "media";
    # 8080 ist von sabnzbd belegt
    webuiPort = 8081;
    # transmission belegt den Default 51413 im selben netns
    torrentingPort = 51414;
    extraArgs = [ "--confirm-legal-notice" ];

    serverConfig = {
      LegalNotice.Accepted = true;

      Preferences.WebUI = {
        Address = "*";
        Username = "aleph";
        # via codeberg.org/feathecutie/qbittorrent_password erzeugen
        Password_PBKDF2 = "@ByteArray(GedoRPUgb3IprDh9zDEW6Q==:Q+JzoEqbaTqEkEIznXVjgQFBfaCM7ERD7T2qMpcOclV+dY4FLwWNkUd+ShBG4F2gnEHy8recMdTRg5eWuwsNpw==)";
      };

      BitTorrent.Session = {
        DefaultSavePath = "/var/lib/qBittorrent/downloads";
        TempPath = "/var/lib/qBittorrent/incomplete";
        TempPathEnabled = true;
        # kein GlobalMaxRatio -> unbegrenzt seeden
        Preallocation = false;
      };
    };
  };

  my.vpn = {
    confinedServices = [ "qbittorrent" ];
    ports = [ 8081 ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/qBittorrent/downloads 0775 qbittorrent media -"
    "d /var/lib/qBittorrent/incomplete 0755 qbittorrent media -"
  ];

  # transmission.nix legt die Gruppe ebenfalls an; das Merge ist konfliktfrei
  users.groups.media = { };
}
