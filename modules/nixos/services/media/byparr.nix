{ ... }:

{
  virtualisation.oci-containers.containers.byparr = {
    image = "ghcr.io/thephaseless/byparr:latest";
    ports = [ ];
    extraOptions = [ "--network=host" ];
    environment = {
      LOG_LEVEL = "info";
    };
  };

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  systemd.services.podman-byparr.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };
}
