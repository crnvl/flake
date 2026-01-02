{
  description = "NixOS flake for cats (home PC), server-ready";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }: {
    nixosConfigurations = {
      cats = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          ./hosts/cats/configuration.nix
          ./modules/nixos/common.nix

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.aleph = {
              home = {
                username = "aleph";
                homeDirectory = "/home/aleph";
                stateVersion = "25.11";

                sessionVariables = {
                  EDITOR = "code";
                  LANG = "en_US.UTF-8";
                };
              };

              programs.firefox = import ./home/firefox.nix;
            };
          }
        ];
      };
    };
  };
}
