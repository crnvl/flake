{ config, pkgs, ... }:

let
  configFile = pkgs.writeText "decluttarr-config.yaml" ''
    general:
      log_level: INFO
      test_run: false
      timer: 10

    jobs:
      remove_failed_downloads:
      remove_failed_imports:
      remove_metadata_missing:
        detect_via_missing_size: true
      remove_missing_files:
      remove_orphans:
      remove_stalled:
      remove_unmonitored:

    instances:
      sonarr:
        - base_url: "http://localhost:8989"
          api_key: !ENV SONARR_API_KEY
      radarr:
        - base_url: "http://localhost:7878"
          api_key: !ENV RADARR_API_KEY
  '';
in
{
  # Contains SONARR_API_KEY=... and RADARR_API_KEY=... lines,
  # consumed as a podman --env-file so the keys never touch the nix store.
  age.secrets.decluttarr-env.file = ../../../../hosts/shimmers/secrets/decluttarr-env.age;

  virtualisation.oci-containers.containers.decluttarr = {
    image = "ghcr.io/manimatter/decluttarr:latest";
    ports = [ ];
    extraOptions = [ "--network=host" ];
    environment = {
      TZ = config.time.timeZone;
    };
    environmentFiles = [ config.age.secrets.decluttarr-env.path ];
    volumes = [ "${configFile}:/app/config/config.yaml:ro" ];
  };

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  virtualisation.podman.autoPrune = {
    enable = true;
    dates = "weekly";
    flags = [ "--all" ];
  };

  # Join the wg netns so it can reach sonarr/radarr (and transmission,
  # for stalled-download data) over localhost, same as recyclarr does.
  my.vpn.confinedServices = [ "podman-decluttarr" ];
}
