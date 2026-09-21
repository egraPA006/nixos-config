{ activeProfiles, config, lib, ... }:

let
  profileGroups = {
    desktop = {
      workstation = { module = ./desktop/workstation.nix; description = "Desktop applications, audio and Bluetooth"; };
      gnome = { module = ./desktop/gnome; description = "GNOME desktop environment"; };
      "gaming-lite" = { module = ./desktop/gaming-lite.nix; description = "Basic gaming tools"; };
      "gaming-full" = { module = ./desktop/gaming-full.nix; description = "Full gaming stack"; };
      "music-lite" = { module = ./desktop/music-lite.nix; description = "Light music workstation"; };
      "music-full" = { module = ./desktop/music-full.nix; description = "Full music workstation"; };
      "guitar-pro" = { module = ./desktop/guitar-pro.nix; description = "Guitar Pro in a separate Wine prefix"; };
      torrent = { module = ./desktop/torrent.nix; description = "Torrent client"; };
      "vpn-client" = { module = ./desktop/services/vpn.nix; description = "AmneziaWG client and explicit WiFi sharing"; };
    };
    development = {
      development = { module = ./development; description = "Git, Codex and Visual Studio Code"; };
    };
    server = {
      "server-web" = { module = ./server/web.nix; description = "Static Caddy website"; };
      "server-vpn" = { module = ./server/vpn.nix; description = "AmneziaWG VPN server"; };
      "server-galene" = { module = ./server/galene.nix; description = "Lightweight video calls and streams"; };
    };
  };
  profileCatalog = lib.mergeAttrsList (builtins.attrValues profileGroups);
  profileModules = lib.mapAttrs (_: profile: profile.module) profileCatalog;
  desktopProfiles = builtins.attrNames profileGroups.desktop;
  serverProfiles = builtins.attrNames profileGroups.server;
  hasActiveProfile = profiles: lib.any (name: builtins.elem name activeProfiles) profiles;
  validProfiles = builtins.attrNames profileModules;
  profileScript = builtins.replaceStrings
    [ "@validProfiles@" "@profileDescriptions@" "@profileGroups@" "@configDir@" ]
    [
      (lib.concatStringsSep " " validProfiles)
      (lib.concatStringsSep " " (map (name: lib.escapeShellArg profileCatalog.${name}.description) validProfiles))
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
    ./desktop/services/options.nix
    ./server/options.nix
  ] ++ map (name: profileModules.${name}) (lib.filter (name: builtins.hasAttr name profileModules) activeProfiles);

  assertions = map (name: {
    assertion = builtins.hasAttr name profileModules;
    message = "Unknown profile '${name}'. Valid: ${lib.concatStringsSep ", " validProfiles}";
  }) activeProfiles ++ [
    {
      assertion = !(builtins.elem "gaming-lite" activeProfiles && builtins.elem "gaming-full" activeProfiles);
      message = "gaming-lite and gaming-full are alternatives; enable only one";
    }
    {
      assertion = !(builtins.elem "music-lite" activeProfiles && builtins.elem "music-full" activeProfiles);
      message = "music-lite and music-full are alternatives; enable only one";
    }
  ];

  pino.subcommands.desktop = lib.mkIf (hasActiveProfile desktopProfiles) {
    description = "Desktop applications and services";
  };

  pino.subcommands.server = lib.mkIf (hasActiveProfile serverProfiles) {
    description = "Server services and connections";
  };

  pino.subcommands.profile = {
    description = "Manage optional NixOS profiles";
    commands = {
      list = {
        description = "List profiles, optionally only enabled names";
        usage = "[--enabled]";
      };
      enable = { description = "Enable a profile and rebuild"; usage = "<profile>"; };
      disable = { description = "Disable a profile and rebuild"; usage = "<profile>"; };
    };
    helpText = ''
      Active profiles: hosts/<hostname>/active-profiles.nix
      Disabling a profile preserves its data.
    '';
    script = profileScript;
    fishCompletions = ''
      complete -c pino -f -n '__fish_pino_at_path profile enable; or __fish_pino_at_path profile disable' \
        -a '${lib.concatStringsSep " " validProfiles}' -d 'Profile name'
      complete -c pino -f -n '__fish_pino_at_path profile list' \
        -l enabled -d 'Print enabled profile names only'
    '';
  };
}
