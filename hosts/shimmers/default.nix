{ ... }:

{
  imports = [
    ./disk-config.nix
    ../../modules/nixos/services/nginx.nix
    ../../modules/nixos/services/kanidm.nix
    ../../modules/nixos/services/jellyfin.nix
    ../../modules/nixos/services/stalwart.nix
  ];

  system.stateVersion = "26.05";
  networking = {
    hostName = "shimmers";
    hosts = {
      "127.0.0.1" = [ "id.shimme.rs" ];
    };
  };
}
