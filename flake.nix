{
  description = "NixOS configuration for re-1 and la1n";

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
  };

  outputs = { self, nixpkgs, home-manager, disko }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    overlays = {
      neural-amp-modeler-lv2-0_2_0 = final: prev: {
        neural-amp-modeler-lv2 = prev.neural-amp-modeler-lv2.overrideAttrs (_: {
          version = "0.2.0";
          src = prev.fetchFromGitHub {
            owner = "mikeoliphant";
            repo  = "neural-amp-modeler-lv2";
            tag   = "v0.2.0";
            fetchSubmodules = true;
            hash  = "sha256-rwh4OGAIw/cLP8Q3kx8mqxUBM2FzLNf9blMgmkwnWpI=";
          };
        });
      };
    };
  in {
    devShells.x86_64-linux.cpp = pkgs.mkShell {
      packages = with pkgs; [
        gcc
        clang
        clang-tools
        meson
        ninja
        pkg-config
        gdb
        cmake
      ];
    };

    nixosConfigurations = {
      re-1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          activeProfiles = import ./hosts/re-1/active-profiles.nix;
        };
        modules = [
          { nixpkgs.overlays = [ overlays.neural-amp-modeler-lv2-0_2_0 ]; }
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          ./hosts/re-1
        ];
      };
      la1n = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          activeProfiles = import ./hosts/la1n/active-profiles.nix;
        };
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          ./hosts/la1n
        ];
      };
    };
  };
}
