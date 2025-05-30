{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, plasma-manager, ... }@inputs: {
    nixosConfigurations = {
      virtualbox = nixpkgs.lib.nixosSystem {
        modules = [
          (./hosts/virtualbox/configuration.nix)
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useUserPackages = true;
              useGlobalPkgs = true;
              users.test = import ./hosts/virtualbox/home.nix; # TODO: change to egrapa
            };
          }
        ];
      };
      laptop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (./hosts/laptop/configuration.nix)
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useUserPackages = true;
              useGlobalPkgs = true;
              extraSpecialArgs = { inherit plasma-manager; };
              users.egrapa = { pkgs, plasma-manager, ... }: {
                imports = [
                  plasma-manager.homeManagerModules.plasma-manager
                  ./hosts/laptop/home.nix
                ];
              };
            };
          }
        ];
      };
    };
  };
}
