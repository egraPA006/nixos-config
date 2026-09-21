# Full music production: Reaper, Wine and yabridge.
{ config, lib, pkgs, ... }:
let
  cfg = config.pino.profiles.musicFull;
  user = config.pino.user;
  installersDir = "${cfg.localDir}/installs";
  pluginsDir = "${cfg.localDir}/plugins/win";
  wine = pkgs.wineWow64Packages.stable;
  reaperPackage = pkgs.reaper.override { jackLibrary = pkgs.pipewire.jack; };
  connectionConfig = pkgs.writeText "reaper-connections.json" (builtins.toJSON cfg.connections);
  connectReaper = pkgs.writeShellScript "reaper-connect" ''
    export PATH=${lib.makeBinPath [ pkgs.pipewire ]}:"$PATH"
    exec ${pkgs.python3}/bin/python3 ${../../../scripts/reaper-connect.py} ${connectionConfig} "$@"
  '';
  reaperMcp = pkgs.python3Packages.buildPythonApplication rec {
    pname = "twelvetake-reaper-mcp";
    version = "1.7.3";
    pyproject = true;
    src = pkgs.fetchPypi {
      pname = "twelvetake_reaper_mcp";
      inherit version;
      hash = "sha256-q8n4DXRSmRyu7d0fh2UIi8dHPt5muyr1fWCG1F7muaU=";
    };
    build-system = [ pkgs.python3Packages.hatchling ];
    dependencies = [ pkgs.python3Packages.mcp ];
    postInstall = ''
      install -Dm444 reaper_mcp_bridge.lua "$out/share/reaper-mcp/reaper_mcp_bridge.lua"
    '';
    pythonImportsCheck = [ "reaper_mcp_server" ];
  };
  offlineWine = pkgs.writeShellScriptBin "music-wine-offline" ''
    exec ${pkgs.bubblewrap}/bin/bwrap --unshare-net --bind / / -- ${wine}/bin/wine "$@"
  '';
  reaperOffline = pkgs.writeShellScriptBin "reaper-offline" ''
    export WINEPREFIX=${lib.escapeShellArg cfg.winePrefix}
    export WINELOADER=${offlineWine}/bin/music-wine-offline
    export YABRIDGE_NO_WATCHDOG=1
    export PIPEWIRE_LATENCY="''${PIPEWIRE_LATENCY:-${toString config.pino.profiles.music.quantum}/48000}"
    exec ${reaperPackage}/bin/reaper "$@"
  '';
  declaredDependencies = lib.unique (lib.concatMap (plugin: plugin.winetricks) (lib.attrValues cfg.windowsPlugins));
  dependencyCommands = lib.concatMapStringsSep "\n" (verb:
    "${pkgs.winetricks}/bin/winetricks -q ${lib.escapeShellArg verb} || return 1"
  ) declaredDependencies;
  installers = lib.mapAttrsToList (name: plugin: { inherit name plugin; }) cfg.windowsPlugins;
  linkedInstallerPatterns = lib.concatStringsSep "|" (map (item: lib.escapeShellArg item.name)
    (lib.filter (item: item.plugin.method == "link") installers));
  orderedInstallers = lib.filter (item: item.plugin.method != "link") installers
    ++ lib.filter (item: item.plugin.method == "link") installers;
  declaredInstallers = lib.concatStringsSep "\n" (map ({ name, plugin }:
    let
      arguments = [ name plugin.installer (if plugin.sha256 == null then "" else plugin.sha256)
        (builtins.hashString "sha256" (builtins.toJSON plugin)) plugin.method ]
        ++ (if plugin.method == "wine" then plugin.args else
          lib.concatLists (lib.mapAttrsToList (source: target: [ source target ])
            (if plugin.method == "link" then plugin.links else plugin.extractedFiles)));
    in ''
      if [ -z "$ONLY_PLUGIN" ] || [ "$ONLY_PLUGIN" = ${lib.escapeShellArg name} ]; then
        install_declared ${lib.escapeShellArgs arguments} || failed=1
        matched=1
      fi
    ''
  ) orderedInstallers);
in
{
  imports = [ ./music-base.nix ];

  config = {
    environment.systemPackages = with pkgs; [
      reaperPackage
      reaperMcp
      surge-xt
      drumgizmo
      yabridge
      yabridgectl
      wineWow64Packages.stable
      winetricks
      carla
    ];

    home-manager.users.${user.name} = {
      xdg.desktopEntries.cockos-reaper = {
        name = "REAPER";
        comment = "REAPER";
        exec = "${reaperOffline}/bin/reaper-offline %F";
        icon = "cockos-reaper";
        categories = [ "Audio" "Video" "AudioVideo" "AudioVideoEditing" "Recorder" ];
        mimeType = [ "application/x-reaper-project" "application/x-reaper-project-backup" "application/x-reaper-theme" ];
      };
      xdg.configFile = {
        "REAPER/Scripts/reaper_mcp_bridge.lua".source = "${reaperMcp}/share/reaper-mcp/reaper_mcp_bridge.lua";
        "REAPER/Scripts/__startup.lua".text = ''
          local bridge = reaper.GetResourcePath() .. "/Scripts/reaper_mcp_bridge.lua"
          local ok, err = pcall(dofile, bridge)
          if not ok then
            reaper.ShowConsoleMsg("REAPER MCP bridge failed: " .. tostring(err) .. "\n")
          end
        '';
        "REAPER/ProjectTemplates/Metal-Sketch.RPP".source = ../../../resources/reaper/ProjectTemplates/Metal-Sketch.RPP;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.localDir} 0755 ${user.name} users -"
      "d ${installersDir} 0755 ${user.name} users -"
      "d ${cfg.localDir}/plugins 0755 ${user.name} users -"
      "d ${pluginsDir} 0755 ${user.name} users -"
    ];

    pino.subcommands.desktop.commands."music-full" = {
      description = "Reaper, Wine installers and yabridge";
      commands = {
        installers.description = "List saved Windows installers";
        install = { description = "Run one saved installer or a path"; usage = "<name|path>"; };
        deps.description = "Install declared Wine dependencies with network access";
        apply = { description = "Install one or all declared Windows plugins and sync yabridge"; usage = "[name] [--force]"; };
        sync.description = "Synchronize yabridge plugins";
        reset-wine.description = "Stop an obsolete Wine server after a system update";
        prefix.description = "Print the Wine prefix path";
        status.description = "Show Wine and yabridge state";
        reaper = { description = "Launch Reaper"; usage = "[samples]"; };
        connect = { description = "Connect Focusrite input 2 and REAPER stereo output"; usage = "[--dry-run]"; };
        quantum = {
          description = "Show or change the global PipeWire quantum without restarting audio";
          usage = "[32|64|128|256|512|1024|auto]";
          helpText = ''
            Default: ${toString config.pino.profiles.music.quantum} samples at 48000 Hz.
            Changes affect the whole PipeWire graph until its next restart.
            auto releases the override and lets clients negotiate the quantum.
          '';
          script = ''
            [ "$#" -le 1 ] || { echo "Usage: pino desktop music-full quantum [samples|auto]" >&2; exit 1; }
            case "''${1:-}" in
              "") ${pkgs.pipewire}/bin/pw-metadata -n settings ;;
              32|64|128|256|512|1024|auto)
                quantum="$1"
                [ "$quantum" != auto ] || quantum=0
                ${pkgs.pipewire}/bin/pw-metadata -n settings 0 clock.force-quantum "$quantum" || exit 1
                echo "PipeWire quantum: $1"
                ;;
              *) echo "Quantum must be 32, 64, 128, 256, 512, 1024 or auto" >&2; exit 1 ;;
            esac
          '';
          fishCompletions = ''
            complete -c pino -f -n '__fish_pino_at_path desktop music-full quantum' \
              -a '32 64 128 256 512 1024 auto' -d 'PipeWire quantum'
          '';
        };
      };
      helpText = ''
        Declare Windows plugins in pino.profiles.musicFull.windowsPlugins, put
        installers or saved libraries in ${installersDir}, then run `apply`
        or `apply <name>` for one plugin.
        Changed installers or arguments are installed again. Optional sha256 is
        the lowercase hex digest from sha256sum. GUI installers may
        still need clicks or license login. Wine and yabridge are prepared
        automatically; default Wine VST2, VST3 and CLAP folders are scanned.
        Declared Winetricks dependencies are installed with network access
        before Wine installers run offline. Inno Setup archives can instead
        be extracted locally. Saved sound libraries can be linked into the
        Wine prefix. REAPER also runs Wine offline.
        For guitar routing, select JACK in REAPER's Audio Device preferences
        with at least two inputs and outputs, then run `pino desktop music-full connect`.
        Input 2 goes to REAPER input 2; master outputs 1/2 go to Focusrite L/R.
        Select mono Input 2 on the guitar track and enable record monitoring.
        Rerun connect after reopening REAPER or reconnecting the interface.
        qpwgraph is available to inspect the routing visually.
      '';
      script = ''
        WINE_PREFIX="${cfg.winePrefix}"
        INSTALLERS="${installersDir}"
        WIN_PLUGINS="${pluginsDir}"
        STAMPS="${cfg.localDir}/installed"

        export WINEPREFIX="$WINE_PREFIX"

        prepare() {
          mkdir -p "$WINE_PREFIX" "$INSTALLERS" "$WIN_PLUGINS" "$STAMPS" || return 1
          if [ ! -f "$WINE_PREFIX/system.reg" ]; then
            echo "Initializing Wine prefix: $WINE_PREFIX"
            mkdir -p "$WINE_PREFIX"
            ${wine}/bin/wineboot --init || return 1
          fi
          for plugin_dir in \
            "$WIN_PLUGINS" \
            "$WINE_PREFIX/drive_c/Program Files/Steinberg/VstPlugins" \
            "$WINE_PREFIX/drive_c/Program Files/VstPlugins" \
            "$WINE_PREFIX/drive_c/Program Files/Common Files/VST3" \
            "$WINE_PREFIX/drive_c/Program Files/Common Files/CLAP"; do
            mkdir -p "$plugin_dir" || return 1
            if ! ${pkgs.yabridgectl}/bin/yabridgectl list 2>/dev/null | grep -Fq "$plugin_dir"; then
              ${pkgs.yabridgectl}/bin/yabridgectl add "$plugin_dir" || return 1
            fi
          done
        }

        run_installer() {
          local installer="$1"
          case "''${installer,,}" in
            *.exe) ${offlineWine}/bin/music-wine-offline "$installer" "''${@:2}" ;;
            *.msi) ${offlineWine}/bin/music-wine-offline msiexec /i "$installer" "''${@:2}" ;;
            *) echo "Unsupported installer: $installer (expected .exe or .msi)" >&2; return 1 ;;
          esac
        }

        install_extracted() (
          local installer="$1" work source target
          shift
          [ "$#" -gt 0 ] || { echo "No extracted files declared" >&2; exit 1; }
          work=$(${pkgs.coreutils}/bin/mktemp -d) || exit 1
          trap '${pkgs.coreutils}/bin/rm -rf "$work"' EXIT
          ${pkgs.bubblewrap}/bin/bwrap --unshare-net --bind / / -- \
            ${pkgs.innoextract}/bin/innoextract --extract --exclude-temp --silent --output-dir "$work" "$installer" || exit 1
          while [ "$#" -ge 2 ]; do
            source="$work/$1"
            target="$WINE_PREFIX/$2"
            shift 2
            if [ -d "$source" ]; then
              ${pkgs.coreutils}/bin/mkdir -p "$target" || exit 1
              ${pkgs.coreutils}/bin/cp -a "$source/." "$target/" || exit 1
            elif [ -f "$source" ]; then
              ${pkgs.coreutils}/bin/install -Dm644 "$source" "$target" || exit 1
            else
              echo "Missing file in Inno Setup archive: $source" >&2
              exit 1
            fi
          done
          [ "$#" -eq 0 ]
        )

        install_links() {
          local directory="$1" source target
          shift
          [ "$#" -gt 0 ] || { echo "No links declared" >&2; return 1; }
          while [ "$#" -ge 2 ]; do
            source="$directory/$1"
            target="$WINE_PREFIX/$2"
            shift 2
            [ -e "$source" ] || { echo "Missing saved content: $source" >&2; return 1; }
            if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
              continue
            fi
            if [ -e "$target" ] || [ -L "$target" ]; then
              echo "Destination already exists: $target" >&2
              return 1
            fi
            mkdir -p "$(dirname "$target")" || return 1
            ln -s "$source" "$target" || return 1
          done
          [ "$#" -eq 0 ]
        }

        install_dependencies() {
          :
          ${lib.optionalString (declaredDependencies != []) ''
            local installed_verbs probe verb missing=0
            if ! probe=$(${wine}/bin/wine cmd.exe /c exit 2>&1); then
              if printf '%s\n' "$probe" | grep -q 'version mismatch'; then
                echo "Wine was updated while its old server was running." >&2
                echo "Close REAPER, then run: pino desktop music-full reset-wine" >&2
              else
                printf '%s\n' "$probe" >&2
              fi
              return 1
            fi
            installed_verbs=$(${pkgs.winetricks}/bin/winetricks list-installed 2>/dev/null) || installed_verbs=""
            for verb in ${lib.escapeShellArgs declaredDependencies}; do
              if ! printf '%s\n' "$installed_verbs" | grep -Fxq "$verb"; then
                missing=1
                break
              fi
            done
            [ "$missing" -eq 0 ] && return 0
            ${dependencyCommands}
            ${wine}/bin/wineserver -k || return 1
            ${pkgs.coreutils}/bin/timeout 30 ${wine}/bin/wineserver -w || return 1
          ''}
        }

        install_declared() {
          local name="$1" filename="$2" expected="$3" signature="$4" method="$5"
          shift 5
          local installer="$INSTALLERS/$filename"
          if [ "$method" = link ]; then
            [ -d "$installer" ] || { echo "Missing saved content for $name: $installer" >&2; return 1; }
            install_links "$installer" "$@" || return 1
            echo "Linked: $name"
            return 0
          fi
          local stamp="$STAMPS/$(printf '%s' "$name" | ${pkgs.coreutils}/bin/sha256sum | cut -d' ' -f1)"
          [ -f "$installer" ] || { echo "Missing installer for $name: $installer" >&2; return 1; }
          local actual
          actual=$(${pkgs.coreutils}/bin/sha256sum "$installer") || return 1
          actual="''${actual%% *}"
          if [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
            echo "Checksum mismatch for $name: $installer" >&2
            return 1
          fi
          if [ "''${FORCE_INSTALL:-0}" != 1 ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$signature $actual" ]; then
            echo "Already installed: $name"
            return 0
          fi
          echo "Installing: $name"
          case "$method" in
            wine) run_installer "$installer" "$@" || return 1 ;;
            innoextract) install_extracted "$installer" "$@" || return 1 ;;
            *) echo "Unsupported installation method: $method" >&2; return 1 ;;
          esac
          printf '%s %s\n' "$signature" "$actual" > "$stamp"
        }

        case "''${1:-}" in
          installers)
            find "$INSTALLERS" -type f \( -iname '*.exe' -o -iname '*.msi' \) -printf '%P\n' 2>/dev/null | sort
            ;;

          install)
            installer="''${2:-}"
            [ -n "$installer" ] || { echo "Usage: pino desktop music-full install <name|path>" >&2; exit 1; }
            [ -f "$installer" ] || installer="$INSTALLERS/$installer"
            [ -f "$installer" ] || { echo "Installer not found: $installer" >&2; exit 1; }
            prepare || exit 1
            run_installer "$installer" || exit 1
            ${pkgs.yabridgectl}/bin/yabridgectl sync
            ;;

          apply)
            ONLY_PLUGIN=""
            FORCE_INSTALL=0
            for arg in "''${@:2}"; do
              case "$arg" in
                --force) FORCE_INSTALL=1 ;;
                *)
                  [ -z "$ONLY_PLUGIN" ] || { echo "Usage: pino desktop music-full apply [name] [--force]" >&2; exit 1; }
                  ONLY_PLUGIN="$arg"
                  ;;
              esac
            done
            prepare || exit 1
            case "$ONLY_PLUGIN" in
              ${if linkedInstallerPatterns == "" then "__no_linked_installers__" else linkedInstallerPatterns}) ;;
              *) install_dependencies || exit 1 ;;
            esac
            failed=0
            matched=0
            ${declaredInstallers}
            [ -z "$ONLY_PLUGIN" ] || [ "$matched" = 1 ] || { echo "Unknown plugin: $ONLY_PLUGIN" >&2; exit 1; }
            ${pkgs.yabridgectl}/bin/yabridgectl sync || failed=1
            exit "$failed"
            ;;

          deps)
            prepare || exit 1
            install_dependencies
            ;;

          sync)
            prepare || exit 1
            ${pkgs.yabridgectl}/bin/yabridgectl sync
            ;;

          reset-wine)
            if ${pkgs.procps}/bin/pgrep -u "$(id -u)" -x reaper >/dev/null || \
               ${pkgs.procps}/bin/pgrep -u "$(id -u)" -f 'yabridge-host' >/dev/null; then
              echo "REAPER or yabridge is still running; close it before resetting Wine" >&2
              exit 1
            fi
            if ${pkgs.procps}/bin/pkill -u "$(id -u)" -TERM -x wineserver 2>/dev/null; then
              echo "Stopped the old Wine server"
            else
              echo "No Wine server is running"
            fi
            ;;

          prefix)
            echo "$WINE_PREFIX"
            ;;

          status)
            [ -f "$WINE_PREFIX/system.reg" ] && ready=yes || ready=no
            echo "Wine ready:   $ready"
            echo "Wine prefix:  $WINE_PREFIX"
            echo "Installers:   $INSTALLERS"
            echo "VST plugins:  $WIN_PLUGINS"
            ${pkgs.yabridgectl}/bin/yabridgectl list 2>/dev/null || true
            ;;

          reaper)
            samples="''${2:-}"
            case "$samples" in ""|32|64|128|256|512|1024) ;; *) echo "Invalid quantum: $samples" >&2; exit 1 ;; esac
            if [ -n "$samples" ]; then
              PIPEWIRE_LATENCY="''${samples}/48000" ${reaperOffline}/bin/reaper-offline &
            else
              ${reaperOffline}/bin/reaper-offline &
            fi
            ;;

          connect)
            shift
            ${connectReaper} "$@"
            ;;

          *)
            echo "Usage: pino desktop music-full installers|install <name|path>|deps|apply [name] [--force]|sync|reset-wine|prefix|status|reaper [samples]|connect [--dry-run]|quantum [samples|auto]"
            exit 1
            ;;
        esac
      '';
      fishCompletions = ''
        complete -c pino -F -n '__fish_pino_at_path desktop music-full install'
        complete -c pino -f -n '__fish_pino_at_path desktop music-full reaper' \
          -a '64 128 256' -d 'PipeWire latency samples'
      '';
    };
  };
}
