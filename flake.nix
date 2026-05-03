{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri.url = "github:sodiboo/niri-flake";
    firefox-addons.url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      # user host helper
      mkHost =
        hostname:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit self inputs; };
          modules = [
            ./hosts/${hostname}
            ./modules/nixos/common.nix
            ./modules/nixos/desktop.nix
            ./modules/nixos/dev.nix
            ./modules/nixos/zsh.nix

            inputs.niri.nixosModules.niri
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = ".bak";
                users.aleph = import ./hosts/${hostname}/users/aleph.nix;
                extraSpecialArgs = { inherit self inputs; };
              };
            }
          ];
        };

      # server host helper
      mkServer =
        hostname:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit self inputs; };
          modules = [
            inputs.disko.nixosModules.disko
            inputs.agenix.nixosModules.default
            ./hosts/${hostname}
            ./modules/nixos/common.nix
            ./modules/nixos/server.nix
            ./modules/nixos/zsh.nix
          ];
        };
    in
    {
      nixosConfigurations = {
        chambers = mkHost "chambers";
        corridors = mkHost "corridors";
        shimmers = mkServer "shimmers";
      };
    };
}
