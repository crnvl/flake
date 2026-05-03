{ ... }:

{
  imports = [
    ./disk-config.nix
  ];

  system.stateVersion = "25.11";
  networking = {
    hostName = "shimmers";
  };
}
