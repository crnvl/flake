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

  virtualisation.podman.autoPrune = {
    enable = true;
    dates = "weekly";
    flags = [ "--all" ];
  };

  my.vpn.confinedServices = [ "podman-byparr" ];
}
