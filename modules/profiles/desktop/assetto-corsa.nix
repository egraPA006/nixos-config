{ config, lib, pkgs, ... }:
let
  cfg = config.pino.profiles.assettoCorsa;
  archiveType = lib.types.submodule {
    options = {
      source = lib.mkOption {
        type = lib.types.str;
        description = "Public HTTPS URL or absolute local ZIP path (use a string for paid archives, never a Nix path).";
      };
      sha256 = lib.mkOption {
        type = lib.types.strMatching "[0-9a-f]{64}";
        description = "SHA-256 hex digest of the ZIP archive.";
      };
      stripPrefix = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Directory inside the ZIP containing the game-relative files.";
      };
      destination = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Destination relative to the game directory, e.g. content/tracks.";
      };
    };
  };
  manifest = pkgs.writeText "assetto-corsa.json" (builtins.toJSON (cfg // {
    fontsDir = "${pkgs.corefonts}/share/fonts/truetype";
  }));
  runner = pkgs.writeShellScriptBin "assetto-corsa-setup" ''
    export PATH=${lib.makeBinPath [ pkgs.curl pkgs.protontricks pkgs.procps ]}:"$PATH"
    export STEAM_EXTRA_COMPAT_TOOLS_PATHS=${lib.escapeShellArg (lib.concatStringsSep ":" (map (p: toString (p.steamcompattool or p)) config.programs.steam.extraCompatPackages))}"''${STEAM_EXTRA_COMPAT_TOOLS_PATHS:+:$STEAM_EXTRA_COMPAT_TOOLS_PATHS}"
    exec ${pkgs.python3}/bin/python3 ${../../../scripts/assetto-corsa.py} ${manifest} "$@"
  '';
in {
  options.pino.profiles.assettoCorsa = {
    gameDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override automatic discovery in native Steam libraries.";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.pino.user.home}/.local/share/pino/assetto-corsa";
    };
    launchOptions = lib.mkOption {
      type = lib.types.str;
      # Wine's newer PDB reader omits symbols required by CSP's Wine mapping.
      default = ''PROTON_ENABLE_WAYLAND=0 WINE_DBGHELP_OLD_PDB=1 WINEDLLOVERRIDES="dwrite=n,b" %command%'';
      description = "Steam launch options for app 244210, applied to local Steam accounts with Steam closed.";
    };
    winetricks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "dotnet48" "d3dcompiler_47" "d3dx11_43" "win10" ];
      description = "Runtime fixes checked against the game's winetricks.log; only missing components are installed. Windows 10 mode is restored after runtime installation.";
    };
    contentManager = lib.mkOption {
      type = archiveType;
      default = {
        source = "https://github.com/gro-ove/actools/releases/download/v0.8.2782.39874/Content.Manager.zip";
        sha256 = "67998c57fc520946f4041152dc3a1f3d5558d4da8062630e9079e31061a21f68";
      };
    };
    csp = lib.mkOption {
      type = lib.types.nullOr archiveType;
      default = null;
      description = "CSP preview ZIP, loaded at runtime from a local path; null leaves CSP untouched.";
    };
    mods = lib.mkOption {
      type = lib.types.listOf archiveType;
      default = [];
      description = "Additional ZIP mods applied in order after CSP (Pure, tracks, cars).";
    };
    videoSettings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = {};
      description = "INI settings merged by graphics; resolution, controls and undeclared keys are preserved.";
    };
    weatherSettings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = {};
      description = "Settings merged into the user's CSP weather_fx.ini by graphics.";
    };
    settings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.attrsOf lib.types.str));
      default = {};
      description = "Game cfg-relative INI files merged on setup (assists, controls and CSP effects). Undeclared keys are preserved.";
    };
    quickDrivePreset = lib.mkOption {
      type = lib.types.nullOr (pkgs.formats.json {}).type;
      default = null;
      description = "Optional Content Manager Quick Drive preset, installed as Pino Drift.cmpreset.";
    };
    quickDrivePresets = lib.mkOption {
      type = lib.types.attrsOf (pkgs.formats.json {}).type;
      default = {};
      description = "Named Content Manager Quick Drive presets; names may include subfolders. Undeclared presets are preserved.";
    };
    extendedPhysicsCars = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[a-zA-Z0-9_-]+");
      default = [];
      description = "Car IDs for which CM enables extended physics, including CSP wet tyre behavior.";
    };
    roadTyreCompounds = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.unsigned;
      default = {};
      description = "Per-car road tyre compound indices selected once in the offline pre-drive menu by a small CSP app. Other setup values are preserved.";
    };
    disableWindowsTransparency = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set CM Disable windows transparency on setup/graphics for Wine compatibility. False leaves the preference untouched.";
    };
  };

  config = {
    pino.artifacts.assetto-corsa.target = "${cfg.stateDir}/installs";
    pino.populate.steps.assetto-corsa = {
      command = [ "pino" "desktop" "assetto-corsa" "setup" ];
      requiresSession = true;
      requiredMount = config.pino.artifacts.assetto-corsa.requiredMount;
      prerequisite = ''exec ${runner}/bin/assetto-corsa-setup check'';
    };
    # Defaults belong on individual keys so selecting a filter does not replace
    # the rest of the base preset through the attrsOf option's default priority.
    pino.profiles.assettoCorsa.videoSettings = lib.mapAttrs (_: lib.mapAttrs (_: lib.mkDefault)) {
      VIDEO = { ANISOTROPIC = "16"; AASAMPLES = "4"; SHADOW_MAP_SIZE = "2048"; };
      EFFECTS = { MOTION_BLUR = "0"; };
      CUBEMAP = { SIZE = "1024"; FACES_PER_FRAME = "1"; };
      MIRROR = { SIZE = "1024"; HQ = "1"; };
      POST_PROCESS = { ENABLED = "1"; QUALITY = "4"; GLARE = "3"; DOF = "0"; };
    };
    environment.systemPackages = [ runner ];
    pino.subcommands.desktop.commands.assetto-corsa = {
      description = "Content Manager, CSP and declared mods for the Steam game";
      commands = {
        status.description = "Find the Steam installation and show declared archives";
        check.description = "Check setup prerequisites without changing files";
        setup.description = "Install dependencies, mods and declared settings";
        apply.description = "Install declared archives, backing up changed files";
        deps.description = "Install missing .NET/DirectX runtimes, core fonts and enable CSP";
        graphics.description = "Apply a high quality base preset, preserving resolution and controls";
        launch-options.description = "Restore declared Steam launch options (close Steam first)";
      };
      script = ''exec ${runner}/bin/assetto-corsa-setup "$@"'';
      helpText = ''
        Install Assetto Corsa in Steam, select Proton-GE, launch once and exit.
        Close the game and Content Manager before apply/deps/graphics.
        Close Steam before apply or launch-options if its launch options need changing.
        Run deps, apply, then optionally graphics. Start the game from Steam.
        apply also restores the declared Steam launch options for local accounts.
        In CM select the game directory and Settings > Content Manager > Drive >
        Game starter: AppID. Disable window transparency if tooltips render black.
        Declare paid ZIPs using local string paths and sha256; activation stays in CM.
        Steam Verify can restore the original launcher: run apply again afterwards.
      '';
    };
  };
}
