# Full music production: Reaper, Wine and yabridge.
{ config, lib, pkgs, ... }:
let
  cfg = config.pino.profiles.musicFull;
  user = config.pino.user;
  installersDir = "${cfg.localDir}/installers";
  pluginsDir = "${cfg.localDir}/plugins/win";
  declaredInstallers = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: plugin:
    "install_declared ${lib.escapeShellArgs (
      [ name plugin.installer (if plugin.sha256 == null then "" else plugin.sha256)
        (builtins.hashString "sha256" (builtins.toJSON plugin)) ] ++ plugin.args
    )} || failed=1"
  ) cfg.windowsPlugins);
in
{
  imports = [ ./music-base.nix ];

  config = {
    environment.systemPackages = with pkgs; [
      reaper
      surge-xt
      drumgizmo
      yabridge
      yabridgectl
      wineWow64Packages.stable
      winetricks
      carla
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.localDir} 0755 ${user.name} users -"
      "d ${installersDir} 0755 ${user.name} users -"
      "d ${pluginsDir} 0755 ${user.name} users -"
    ];

    pino.subcommands.desktop.commands."music-full" = {
      description = "Reaper, Wine installers and yabridge";
      commands = {
        installers.description = "List saved Windows installers";
        install = { description = "Run one saved installer or a path"; usage = "<name|path>"; };
        install-all.description = "Run every saved installer in name order";
        apply = { description = "Install declared Windows plugins and sync yabridge"; usage = "[--force]"; };
        sync.description = "Synchronize yabridge plugins";
        prefix.description = "Print the Wine prefix path";
        status.description = "Show Wine and yabridge state";
        reaper = { description = "Launch Reaper"; usage = "[samples]"; };
      };
      helpText = ''
        Declare Windows plugins in pino.profiles.musicFull.windowsPlugins, put
        their .exe or .msi installers in ${installersDir}, then run `apply`.
        Changed installers or arguments are installed again. Optional sha256 is
        the lowercase hex digest from sha256sum. GUI installers may
        still need clicks or license login. Wine and yabridge are prepared
        automatically; default Wine VST2, VST3 and CLAP folders are scanned.
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
            ${pkgs.wineWow64Packages.stable}/bin/wineboot --init || return 1
            ${pkgs.wineWow64Packages.stable}/bin/wineserver -w || return 1
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
            *.exe) ${pkgs.wineWow64Packages.stable}/bin/wine "$installer" "''${@:2}" ;;
            *.msi) ${pkgs.wineWow64Packages.stable}/bin/wine msiexec /i "$installer" "''${@:2}" ;;
            *) echo "Unsupported installer: $installer (expected .exe or .msi)" >&2; return 1 ;;
          esac
        }

        install_declared() {
          local name="$1" filename="$2" expected="$3" signature="$4"
          shift 4
          local installer="$INSTALLERS/$filename"
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
          run_installer "$installer" "$@" || return 1
          ${pkgs.wineWow64Packages.stable}/bin/wineserver -w || return 1
          printf '%s %s\n' "$signature" "$actual" > "$stamp"
        }

        case "''${1:-}" in
          installers)
            find "$INSTALLERS" -maxdepth 1 -type f \( -iname '*.exe' -o -iname '*.msi' \) -printf '%f\n' 2>/dev/null | sort
            ;;

          install)
            installer="''${2:-}"
            [ -n "$installer" ] || { echo "Usage: pino desktop music-full install <name|path>" >&2; exit 1; }
            [ -f "$installer" ] || installer="$INSTALLERS/$installer"
            [ -f "$installer" ] || { echo "Installer not found: $installer" >&2; exit 1; }
            prepare || exit 1
            run_installer "$installer" || exit 1
            ${pkgs.wineWow64Packages.stable}/bin/wineserver -w || exit 1
            ${pkgs.yabridgectl}/bin/yabridgectl sync
            ;;

          install-all)
            prepare || exit 1
            found=0
            failed=0
            while IFS= read -r -d "" installer; do
              found=1
              echo "=== $(basename "$installer") ==="
              run_installer "$installer" || failed=1
            done < <(find "$INSTALLERS" -maxdepth 1 -type f \( -iname '*.exe' -o -iname '*.msi' \) -print0 | sort -z)
            [ "$found" = 1 ] || echo "No installers in $INSTALLERS"
            ${pkgs.wineWow64Packages.stable}/bin/wineserver -w || failed=1
            ${pkgs.yabridgectl}/bin/yabridgectl sync || failed=1
            exit "$failed"
            ;;

          apply)
            case "''${2:-}" in
              "") FORCE_INSTALL=0 ;;
              --force) FORCE_INSTALL=1 ;;
              *) echo "Usage: pino desktop music-full apply [--force]" >&2; exit 1 ;;
            esac
            prepare || exit 1
            failed=0
            ${declaredInstallers}
            ${pkgs.yabridgectl}/bin/yabridgectl sync || failed=1
            exit "$failed"
            ;;

          sync)
            prepare || exit 1
            ${pkgs.yabridgectl}/bin/yabridgectl sync
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
            if [ -n "$samples" ]; then
              PIPEWIRE_LATENCY="''${samples}/48000" reaper &
            else
              reaper &
            fi
            ;;

          *)
            echo "Usage: pino desktop music-full installers|install <name|path>|install-all|apply [--force]|sync|prefix|status|reaper [samples]"
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
