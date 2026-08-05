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
        DefaultSavePath = "/var/lib/qBittorrent/downloads";
        TempPath = "/var/lib/qBittorrent/incomplete";
        TempPathEnabled = true;
        Preallocation = false;

        GlobalMaxRatio = 2.0;
        GlobalMaxRatioAction = 0;
        GlobalMaxInactiveSeedingMinutes = 20160;
        QueueingSystemEnabled = false;

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

  systemd.services.qbittorrent.serviceConfig = {
    LimitNOFILE = 65536;
    UMask = "0002";
  };

  my.vpn = {
    confinedServices = [ "qbittorrent" ];
    ports = [ 8081 ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/qBittorrent/downloads 0775 qbittorrent media -"
    "d /var/lib/qBittorrent/incomplete 0755 qbittorrent media -"
  ];

  users.groups.media = { };
}
