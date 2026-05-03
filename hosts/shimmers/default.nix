{ ... }:

{
  imports = [
    ./disk-config.nix
    ../../modules/nixos/services/nginx.nix
    ../../modules/nixos/services/kanidm.nix
  ];

  system.stateVersion = "26.05";
  networking = {
    hostName = "shimmers";
  };
}
