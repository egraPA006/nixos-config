{ activeProfiles, lib, ... }:

let
  profileModules = {
    codex = ./codex.nix;
    git = ./git.nix;
    gnome = ./gnome;
    vscode = ./vscode.nix;
    vpn = ./vpn.nix;
    hotspot = ./hotspot.nix;
    "gaming-lite" = ./gaming-lite.nix;
    "gaming-full" = ./gaming-full.nix;
    "music-lite" = ./music-lite.nix;
    "music-full" = ./music-full.nix;
    "dev-cpp" = ./dev-cpp.nix;
    torrent = ./torrent.nix;
    vault = ./vault.nix;
  };
  validProfiles = builtins.attrNames profileModules;
  profileScript = builtins.replaceStrings
    [ "@validProfiles@" ]
    [ (lib.concatStringsSep " " validProfiles) ]
    (builtins.readFile ../pino/profile.sh);
in
{
  imports = [ ./options.nix ]
    ++ map (name: profileModules.${name}) (lib.filter (name: builtins.hasAttr name profileModules) activeProfiles);

  assertions = map (name: {
    assertion = builtins.hasAttr name profileModules;
    message = "Unknown profile '${name}'. Valid: ${lib.concatStringsSep ", " validProfiles}";
  }) activeProfiles;

  pino.subcommands.profile = {
    description = "Manage optional NixOS profiles";
    commands = {
      list.description = "List available profiles";
      status.description = "Show active profiles";
      enable = { description = "Enable a profile and rebuild"; usage = "<profile>"; };
      disable = { description = "Disable a profile and rebuild"; usage = "<profile>"; };
    };
    helpText = ''
      pino profile — manage optional profiles
        pino profile list
        pino profile status
        pino profile enable  <name>
        pino profile disable <name>

      Active profiles: hosts/<hostname>/active-profiles.nix
      Disabling a profile preserves its data.
    '';
    script = profileScript;
    fishCompletions = ''
      set -l profile_cmds list status enable disable
      complete -c pino -f -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from $profile_cmds' -a list -d 'List profiles'
      complete -c pino -f -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from $profile_cmds' -a status -d 'Show active profiles'
      complete -c pino -f -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from $profile_cmds' -a enable -d 'Enable a profile'
      complete -c pino -f -n '__fish_seen_subcommand_from profile; and not __fish_seen_subcommand_from $profile_cmds' -a disable -d 'Disable a profile'
      complete -c pino -f -n '__fish_seen_subcommand_from enable disable' -a '${lib.concatStringsSep " " validProfiles}' -d 'Profile name'
    '';
  };
}
