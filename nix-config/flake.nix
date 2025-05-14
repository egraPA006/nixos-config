{
  description = "NixOS configuration with profile selection (laptop/qemu/etc)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: let
    # Supported system profiles (add more as needed)
    supportedSystems = [ "laptop" "qemu" "minimal" ];
    # !!! USER CONFIG: Change this to switch profiles !!!
    selectedSystem = "laptop";  # Options: ${toString supportedSystems}
  in {
    # Validate selected profile and build configuration
    nixosConfigurations = 
      if builtins.elem selectedSystem supportedSystems then {
        "${selectedSystem}" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";  # Or dynamically detect (e.g., aarch64)
          modules = [
            # Conditionally import hardware.nix if it exists
            (./hosts + "/${selectedSystem}/hardware.nix")
            # Main profile config (required)
            (./hosts + "/${selectedSystem}/default.nix")
            # Home Manager integration
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useUserPackages = true;
                useGlobalPkgs = true;
                users.yourusername = import ./home/core.nix;
                extraSpecialArgs = { inherit inputs selectedSystem; };
              };
            }
          ];
          specialArgs = { inherit inputs selectedSystem; };
        };
      } else throw ''
        Unsupported system profile: "${selectedSystem}".
        Valid options: ${toString supportedSystems}
      '';
  };
}