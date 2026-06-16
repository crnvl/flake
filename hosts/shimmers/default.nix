{ ... }:

{
  imports = [
    ./disk-config.nix

    ../../modules/nixos/boxes/chroma.nix

    ../../modules/nixos/services/nginx.nix
    ../../modules/nixos/services/kanidm.nix
    ../../modules/nixos/services/jellyfin.nix
    ../../modules/nixos/services/transmission.nix
    ../../modules/nixos/services/vpn.nix
    ../../modules/nixos/services/monero.nix

    ../../modules/nixos/services/media/prowlarr.nix
    ../../modules/nixos/services/media/sonarr.nix
    ../../modules/nixos/services/media/radarr.nix
    ../../modules/nixos/services/media/seerr.nix
    ../../modules/nixos/services/media/byparr.nix

    ../../modules/nixos/services/caelo.nix
    ../../modules/nixos/services/catshift.nix
  ];

  system.stateVersion = "26.05";
  networking = {
    hostName = "shimmers";
    hosts = {
      "127.0.0.1" = [ "id.shimme.rs" ];
    };
  };
}
