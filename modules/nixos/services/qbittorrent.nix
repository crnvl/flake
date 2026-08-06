{ config, ... }:

let
  wgNamespace = config.vpnNamespaces."wg";
in
{
  services.qbittorrent = {
    enable = true;
    group = "media";
    webuiPort = 8081;
    torrentingPort = 51414;
    extraArgs = [ "--confirm-legal-notice" ];

    serverConfig = {
      LegalNotice.Accepted = true;

      Preferences.WebUI = {
        Address = wgNamespace.namespaceAddress;
        Username = "aleph";
        Password_PBKDF2 = ''"@ByteArray(GedoRPUgb3IprDh9zDEW6Q==:Q+JzoEqbaTqEkEIznXVjgQFBfaCM7ERD7T2qMpcOclV+dY4FLwWNkUd+ShBG4F2gnEHy8recMdTRg5eWuwsNpw==)"'';
      };

      BitTorrent.Session = {
        DefaultSavePath = "/mnt/chroma/downloads";
        TempPath = "/var/lib/qBittorrent/incomplete";
        TempPathEnabled = true;
        Preallocation = false;

        GlobalMaxRatio = 1.0;
        GlobalMaxSeedingMinutes = 4320; # 3 Tage aktives Seeding
        GlobalMaxInactiveSeedingMinutes = 1440; # 1 Tag ohne Aktivität
        GlobalMaxRatioAction = 3; # Torrent + Dateien entfernen

        QueueingSystemEnabled = true;
        MaxActiveDownloads = 5;
        MaxActiveUploads = -1;
        MaxActiveTorrents = -1;

        ConnectionSpeed = 100;
        MaxConnections = 2000;
        MaxConnectionsPerTorrent = 300;
        MaxUploads = 50;
        MaxUploadsPerTorrent = 8;

        PeerTurnover = 10;
        PeerTurnoverCutoff = 90;
        PeerTurnoverInterval = 300;

        SendBufferWatermark = 10240;
        SendBufferLowWatermark = 1024;
        SendBufferWatermarkFactor = 200;
        SocketBacklogSize = 100;

        BTProtocol = "Both";
        Encryption = 0;

        DHTEnabled = true;
        PeXEnabled = true;
        LSDEnabled = false;

        AnonymousModeEnabled = false;
      };
    };
  };

  systemd.services.qbittorrent = {
    serviceConfig = {
      LimitNOFILE = 65536;
      UMask = "0002";
    };
    unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];
  };

  my.vpn = {
    confinedServices = [ "qbittorrent" ];
    ports = [ 8081 ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/qBittorrent/incomplete 0755 qbittorrent media -"
  ];
}
