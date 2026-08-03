{ activeProfiles, config, lib, ... }:

let
  profileGroups = {
    desktop = {
      "desktop-apps" = ./desktop/apps.nix;
      "desktop-audio" = ./desktop/audio.nix;
      "desktop-bluetooth" = ./desktop/bluetooth.nix;
      gnome = ./desktop/gnome;
      vscode = ./desktop/vscode.nix;
      "gaming-lite" = ./desktop/gaming-lite.nix;
      "gaming-full" = ./desktop/gaming-full.nix;
      "music-lite" = ./desktop/music-lite.nix;
      "music-full" = ./desktop/music-full.nix;
      torrent = ./desktop/torrent.nix;
    };
    development = {
      codex = ./development/codex.nix;
      git = ./development/git.nix;
      "dev-cpp" = ./development/dev-cpp.nix;
    };
    network = {
      vpn = ./network/vpn.nix;
      hotspot = ./network/hotspot.nix;
    };
    security.vault = ./security/vault;
    storage = {
      datasets = ./storage/datasets.nix;
      snapshots = ./storage/snapshots.nix;
    };
    system."system-monitor" = ./system/monitor.nix;
  };
  profileModules = lib.mergeAttrsList (builtins.attrValues profileGroups);
  desktopProfiles = builtins.attrNames profileGroups.desktop;
  networkProfiles = builtins.attrNames profileGroups.network;
  storageProfiles = (builtins.attrNames profileGroups.storage) ++ [ "vault" ];
  hasActiveProfile = profiles: lib.any (name: builtins.elem name activeProfiles) profiles;
  validProfiles = builtins.attrNames profileModules;
  profileScript = builtins.replaceStrings
    [ "@validProfiles@" "@profileGroups@" "@configDir@" ]
    [
      (lib.concatStringsSep " " validProfiles)
      (lib.concatStringsSep " " (lib.mapAttrsToList
        (group: profiles: "'${group}:${lib.concatStringsSep "," (builtins.attrNames profiles)}'")
        profileGroups))
      config.pino.configDir
    ]
    (builtins.readFile ../pino/profile.sh);
in
{
  imports = [
    ./desktop/options.nix
    ./network/options.nix
    ./security/vault/options.nix
  ] ++ map (name: profileModules.${name}) (lib.filter (name: builtins.hasAttr name profileModules) activeProfiles);

  assertions = map (name: {
    assertion = builtins.hasAttr name profileModules;
    message = "Unknown profile '${name}'. Valid: ${lib.concatStringsSep ", " validProfiles}";
  }) activeProfiles;

  pino.subcommands.desktop = lib.mkIf (hasActiveProfile desktopProfiles) {
    description = "Desktop applications and services";
  };

  pino.subcommands.network = lib.mkIf (hasActiveProfile networkProfiles) {
    description = "Network services";
  };

  pino.subcommands.storage = lib.mkIf (hasActiveProfile storageProfiles) {
    description = "Local and removable storage";
  };

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
      complete -c pino -f -n '__fish_pino_at_path profile enable; or __fish_pino_at_path profile disable' \
        -a '${lib.concatStringsSep " " validProfiles}' -d 'Profile name'
    '';
  };
}
