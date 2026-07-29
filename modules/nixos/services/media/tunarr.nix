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
      "/mnt/chroma:/mnt/chroma:ro"
    ];
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
