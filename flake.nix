{
  description = "aleph's nixos flake :3";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    
  };

  outputs = { self, nixpkgs }: {

    # NixOS system configuration
    nixosConfigurations = {
      system = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix
        ];
      };
    };
  };
}
