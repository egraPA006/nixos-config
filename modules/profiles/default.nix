{ activeProfiles, lib, pkgs, ... }:
let
  validProfiles = [
    "gaming-lite" "gaming-full"
    "virt-general" "virt-osdev"
    "music-lite" "music-full"
    "dev-cpp"
  ];

  nixosProfile = pkgs.writeShellApplication {
    name = "nixos-profile";
    runtimeInputs = with pkgs; [ coreutils gnugrep bash ];
    text = builtins.readFile ../../scripts/nixos-profile.sh;
  };
in
{
  imports = map (p: ./. + "/${p}.nix") activeProfiles;

  assertions = map (p: {
    assertion = lib.elem p validProfiles;
    message = "Unknown profile '${p}' in active-profiles.nix. Valid: ${lib.concatStringsSep ", " validProfiles}";
  }) activeProfiles;

  environment.systemPackages = [ nixosProfile ];
}
