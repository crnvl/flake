{ config, ... }:

{
  virtualisation.oci-containers.containers.tunarr = {
    image = "ghcr.io/chrisbenincasa/tunarr:latest";
    ports = [ ];
    extraOptions = [ "--network=host" ];
    environment = {
      TZ = config.time.timeZone;
      TUNARR_LOG_LEVEL = "info";
      TUNARR_BIND_ADDR = "127.0.0.1";
    };
    volumes = [
      "/var/lib/tunarr:/config/tunarr"
      "/etc/localtime:/etc/localtime:ro"
      "/mnt/chroma:/mnt/chroma:ro"
    ];
  };

  # Jellyfin's XMLTV parser loses the <icon> that follows Tunarr's <image>
  # element, so programmes end up without artwork. Point Jellyfin's guide at
  # http://127.0.0.1:8742/api/xmltv.xml, which comments the <image> tags out.
  services.nginx.virtualHosts."tunarr-xmltv" = {
    listen = [
      {
        addr = "127.0.0.1";
        port = 8742;
      }
    ];
    locations."/api/xmltv.xml" = {
      proxyPass = "http://127.0.0.1:8000";
      recommendedProxySettings = false;
      extraConfig = ''
        proxy_set_header Host 127.0.0.1:8000;
        proxy_set_header Accept-Encoding "";
        sub_filter_types application/xml text/xml;
        sub_filter_once off;
        sub_filter '<image size="1">' '<!--';
        sub_filter '<image size="2">' '<!--';
        sub_filter '<image size="3">' '<!--';
        sub_filter '</image>' '-->';
      '';
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/tunarr 0755 root root -"
  ];

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  virtualisation.podman.autoPrune = {
    enable = true;
    dates = "weekly";
    flags = [ "--all" ];
  };
}
