{
  description = "aleph's nixos flake :3";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
    nixosModules.url = "github:nixos/nixos";
  };

  outputs = { self, nixpkgs, nixosModules }: {

    # NixOS system configuration
    nixosConfigurations = {
      mySystem = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix
        ];
      };
    };
  };
}
