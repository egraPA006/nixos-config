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

  pino.subcommands.profile = {
    description = "Manage NixOS profiles  (gaming, dev-cpp, ...)";
    helpText = ''
      pino profile — manage NixOS profiles
        pino profile list               List available profiles
        pino profile status             Show active profiles on this machine
        pino profile enable  <name>     Enable a profile and rebuild
        pino profile disable <name>     Disable a profile and rebuild

        Active profiles: hosts/<hostname>/active-profiles.nix
    '';
    script = ''nixos-profile "$@"'';
  };
}
