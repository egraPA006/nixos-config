{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
              sharedModules = [ plasma-manager.homeManagerModules.plasma-manager ];
              users.egrapa = import ./hosts/laptop/home.nix;
            };
          }
        ];
      };
    };
  };
}
