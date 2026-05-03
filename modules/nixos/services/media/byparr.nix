{ ... }:

{
  virtualisation.oci-containers.containers.byparr = {
    image = "ghcr.io/thephasdin/byparr:latest";
    ports = [ "8191:8191" ];
    environment = {
      LOG_LEVEL = "info";
    };
  };

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";
}
