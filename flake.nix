{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: {
    nixosConfigurations = {
      virtualbox = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (./hosts/virtualbox/configuration.nix)
          # home-manager.nixosModules.home-manager
          # {
          #   home-manager = {
          #     useUserPackages = true;
          #     useGlobalPkgs = true;
          #     users.test = import ./hosts/virtualbox/home.nix;
          #   };
          # }
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
              users.egrapa = import ./hosts/laptop/home.nix;
            };
          }
        ];
      };
    };
  };
}