{ mkProxyHost, ... }:

{
  services.navidrome = {
    enable = true;
    openFirewall = false;

    settings = {
      Address = "127.0.0.1";
      Port = 4533;
      MusicFolder = "/mnt/chroma/music";

      # No inotify over CIFS, so the folder watcher is useless; rescan on a
      # schedule instead. Lidarr can also trigger a scan right after imports
      # via a Subsonic connection (Settings > Connect) pointed at navidrome.
      Scanner = {
        WatcherWait = "0";
        Schedule = "@every 1h";
      };
    };
  };

  # The library is 0664/0775 jellyfin:media on the CIFS mount, so the world
  # read bits suffice; navidrome runs with PrivateUsers=true, under which
  # supplementary groups like media would be unmapped anyway.
  systemd.services.navidrome.unitConfig.RequiresMountsFor = [ "/mnt/chroma" ];

  services.nginx.virtualHosts."music.shimme.rs" = mkProxyHost { port = 4533; };
}
