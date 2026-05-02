{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
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
    {
      nixosConfigurations = {
        cats = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit self inputs; };
          modules = [
            ./hosts/chambers

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

                users.aleph = import ./hosts/chambers/users/aleph.nix;
                extraSpecialArgs = { inherit inputs; };
              };
            }
          ];
        };
      };
    };
}
