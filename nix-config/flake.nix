{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: let
    supportedSystems = [ "laptop" "virtualbox" ];
    # !!! USER CONFIG: Change this to switch profiles !!!
    selectedSystem = "virtualbox";
  in {
    nixosConfigurations =  {
      "${selectedSystem}" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (./hosts + "/${selectedSystem}.nix")
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useUserPackages = true;
              useGlobalPkgs = true;
              users.egrapa = import ./home/home.nix;
              extraSpecialArgs = { inherit inputs selectedSystem; };
            };
          }
        ];
        specialArgs = { inherit inputs selectedSystem; };
      };
    };
  };
}