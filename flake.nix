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

  outputs = { nixpkgs, home-manager, disko, ... }:
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

    mkHost = name: extraModules: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs.activeProfiles = import (./hosts + "/${name}/active-profiles.nix");
      modules = [
        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
      ] ++ extraModules ++ [ (./hosts + "/${name}") ];
    };
    re1 = mkHost "re-1" [
      { nixpkgs.overlays = [ overlays.neural-amp-modeler-lv2-0_2_0 ]; }
    ];
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
      re-1 = re1;
      la1n = mkHost "la1n" [ ];
    };

    checks.x86_64-linux.re-1 = re1.config.system.build.toplevel;
  };
}
