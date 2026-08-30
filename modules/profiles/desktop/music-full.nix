# Full music production: Reaper, Wine and yabridge.
{ config, pkgs, ... }:
let
  cfg = config.pino.profiles.musicFull;
  user = config.pino.user;
  installersDir = "${cfg.localDir}/installers";
  pluginsDir = "${cfg.localDir}/plugins/win";
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
        sync.description = "Synchronize yabridge plugins";
        prefix.description = "Print the Wine prefix path";
        status.description = "Show Wine and yabridge state";
        reaper = { description = "Launch Reaper"; usage = "[samples]"; };
      };
      helpText = ''
        Put .exe or .msi installers in ${installersDir}, restore that directory
        from a backup on a new system, then run each installer. Wine is prepared
        automatically. Install VST files into ${pluginsDir}; run `sync` afterwards.
      '';
      script = ''
        WINE_PREFIX="${cfg.winePrefix}"
        INSTALLERS="${installersDir}"
        WIN_PLUGINS="${pluginsDir}"

        export WINEPREFIX="$WINE_PREFIX"

        prepare() {
          mkdir -p "$WINE_PREFIX" "$INSTALLERS" "$WIN_PLUGINS"
          if [ ! -f "$WINE_PREFIX/system.reg" ]; then
            echo "Initializing Wine prefix: $WINE_PREFIX"
            mkdir -p "$WINE_PREFIX"
            ${pkgs.wineWow64Packages.stable}/bin/wineboot --init
            ${pkgs.wineWow64Packages.stable}/bin/wineserver -w
          fi
          if ! ${pkgs.yabridgectl}/bin/yabridgectl list 2>/dev/null | grep -Fq "$WIN_PLUGINS"; then
            ${pkgs.yabridgectl}/bin/yabridgectl add "$WIN_PLUGINS"
          fi
        }

        run_installer() {
          local installer="$1"
          case "''${installer,,}" in
            *.exe) ${pkgs.wineWow64Packages.stable}/bin/wine "$installer" ;;
            *.msi) ${pkgs.wineWow64Packages.stable}/bin/wine msiexec /i "$installer" ;;
            *) echo "Unsupported installer: $installer (expected .exe or .msi)" >&2; return 1 ;;
          esac
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
            prepare
            run_installer "$installer"
            ;;

          install-all)
            prepare
            found=0
            while IFS= read -r -d "" installer; do
              found=1
              echo "=== $(basename "$installer") ==="
              run_installer "$installer"
            done < <(find "$INSTALLERS" -maxdepth 1 -type f \( -iname '*.exe' -o -iname '*.msi' \) -print0 | sort -z)
            [ "$found" = 1 ] || echo "No installers in $INSTALLERS"
            ;;

          sync)
            prepare
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
            echo "Usage: pino desktop music-full installers|install <name|path>|install-all|sync|prefix|status|reaper [samples]"
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
