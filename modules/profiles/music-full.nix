# Full music production: Reaper DAW + yabridge for Windows VST/VST3 plugins.
# Windows plugins: place DLLs in data/music-full/plugins/win (repo) — they sync to
# localDir/plugins/win and are bridged via yabridge into localDir/plugins/linux-bridged.
# Linux plugins: place .so files in data/music-full/plugins/linux — they sync to
# localDir/plugins/linux.
# Wine prefix lives at musicFull.winePrefix (for installer-based plugins like Neural DSP).
{ config, pkgs, ... }:
let
  cfg       = config.musicFull;
  configDir = "/home/egrapa/nixos-config";
  srcDir    = "${configDir}/data/music-full";

  wineNonet = pkgs.writeShellScriptBin "wine-nonet" ''
    exec ${pkgs.firejail}/bin/firejail --net=none ${pkgs.wineWow64Packages.stable}/bin/wine64 "$@"
  '';
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
      wineNonet
    ];

    programs.firejail.enable = true;

    system.activationScripts.music-full-sync.text = ''
      parent="$(dirname "${cfg.localDir}")"
      if [ -d "$parent" ]; then
        mkdir -p "${cfg.localDir}/plugins/linux"
        mkdir -p "${cfg.localDir}/plugins/win"
        mkdir -p "${cfg.localDir}/plugins/linux-bridged"
        mkdir -p "${cfg.localDir}/nki"
        ${pkgs.rsync}/bin/rsync -a "${srcDir}/plugins/linux/" "${cfg.localDir}/plugins/linux/"
        ${pkgs.rsync}/bin/rsync -a "${srcDir}/plugins/win/"   "${cfg.localDir}/plugins/win/"
        ${pkgs.rsync}/bin/rsync -a "${srcDir}/nki/"           "${cfg.localDir}/nki/"
        chown -R egrapa:users "${cfg.localDir}"

        yabridgectl_cfg="/home/egrapa/.config/yabridgectl/config.toml"
        mkdir -p "$(dirname "$yabridgectl_cfg")"
        if ! grep -qF "${cfg.localDir}/plugins/win" "$yabridgectl_cfg" 2>/dev/null; then
          printf '\n[[directories]]\npath = "%s"\n' "${cfg.localDir}/plugins/win" >> "$yabridgectl_cfg"
        fi
        chown -R egrapa:users "/home/egrapa/.config/yabridgectl"

        yabridge_cfg="/home/egrapa/.config/yabridge/config.toml"
        mkdir -p "$(dirname "$yabridge_cfg")"
        printf '[yabridge]\nwine-binary = "%s"\n' "${wineNonet}/bin/wine-nonet" > "$yabridge_cfg"
        chown -R egrapa:users "/home/egrapa/.config/yabridge"
      else
        echo "music-full-sync: $parent not available, skipping" >&2
      fi
    '';

    pino.subcommands."music-full" = {
      description = "Reaper + yabridge Windows VST bridge + plugin management";
      helpText = ''
        pino music-full — manage full music production setup
          pino music-full list              List Linux and bridged Windows plugins
          pino music-full setup             Init Wine prefix and configure yabridge
          pino music-full bridge            Sync yabridge (update .so bridges for Win plugins)
          pino music-full bridge-add <dir>  Register a Win plugin directory with yabridge
          pino music-full install <exe>        Run a Windows plugin installer (with network)
          pino music-full install-nonet <exe>  Run a Windows plugin installer (network blocked)
          pino music-full reaper [samples]  Launch Reaper (with optional PIPEWIRE_LATENCY, e.g. 128)
          pino music-full prefix            Print Wine prefix path
          pino music-full status            Show plugin counts

        Plugin source dirs (commit .dll/.so files here):
          Windows: ${srcDir}/plugins/win/
          Linux:   ${srcDir}/plugins/linux/
          NKI:     ${srcDir}/nki/

        Fast local dirs (synced on rebuild, read by Reaper):
          Windows DLLs:    ${cfg.localDir}/plugins/win/
          Linux plugins:   ${cfg.localDir}/plugins/linux/
          Bridged (.so):   ${cfg.localDir}/plugins/linux-bridged/
          NKI instruments: ${cfg.localDir}/nki/
          Wine prefix:     ${cfg.winePrefix}
      '';
      script = ''
        WINE_PREFIX="${cfg.winePrefix}"
        WIN_PLUGINS="${cfg.localDir}/plugins/win"
        LINUX_PLUGINS="${cfg.localDir}/plugins/linux"
        BRIDGED_DIR="${cfg.localDir}/plugins/linux-bridged"

        export WINEPREFIX="$WINE_PREFIX"

        case "''${1:-}" in
          list)
            echo "=== Linux plugins ($LINUX_PLUGINS) ==="
            count=0
            shopt -s nullglob
            for f in "$LINUX_PLUGINS"/*.so "$LINUX_PLUGINS"/*.vst3; do
              echo "  $(basename "$f")"
              count=$(( count + 1 ))
            done
            shopt -u nullglob
            [ "$count" = 0 ] && echo "  (none)"

            echo ""
            echo "=== Bridged Windows plugins ($BRIDGED_DIR) ==="
            count=0
            shopt -s nullglob
            for f in "$BRIDGED_DIR"/*.so; do
              echo "  $(basename "$f")"
              count=$(( count + 1 ))
            done
            shopt -u nullglob
            [ "$count" = 0 ] && echo "  (none — run 'pino music-full bridge' after installing Win plugins)"
            ;;

          setup)
            echo "Initializing Wine prefix: $WINE_PREFIX"
            mkdir -p "$WINE_PREFIX"
            ${pkgs.wineWow64Packages.stable}/bin/wineboot --init
            echo ""
            echo "Configuring yabridge output dir: $BRIDGED_DIR"
            mkdir -p "$BRIDGED_DIR"
            ${pkgs.yabridgectl}/bin/yabridgectl add "$WIN_PLUGINS"
            echo ""
            echo "Done. Install Windows plugins with:"
            echo "  pino music-full install <Installer.exe>"
            echo "Then run: pino music-full bridge"
            ;;

          bridge)
            echo "Syncing yabridge bridges..."
            ${pkgs.yabridgectl}/bin/yabridgectl sync
            echo ""
            echo "Bridged plugins (.so) are in: $BRIDGED_DIR"
            echo "Point Reaper VST scan to that directory."
            ;;

          bridge-add)
            dir="''${2:-}"
            [ -z "$dir" ] && { echo "Usage: pino music-full bridge-add <directory>"; exit 1; }
            ${pkgs.yabridgectl}/bin/yabridgectl add "$dir"
            echo "Added. Run 'pino music-full bridge' to create .so files."
            ;;

          install)
            exe="''${2:-}"
            [ -z "$exe" ] && { echo "Usage: pino music-full install <Installer.exe>"; exit 1; }
            [ ! -f "$exe" ] && { echo "File not found: $exe"; exit 1; }
            echo "Running installer in Wine prefix: $WINE_PREFIX"
            ${pkgs.wineWow64Packages.stable}/bin/wine "$exe"
            echo ""
            echo "After installation, run: pino music-full bridge"
            ;;

          install-nonet)
            exe="''${2:-}"
            [ -z "$exe" ] && { echo "Usage: pino music-full install-nonet <Installer.exe>"; exit 1; }
            [ ! -f "$exe" ] && { echo "File not found: $exe"; exit 1; }
            echo "Running installer in Wine prefix: $WINE_PREFIX (network blocked)"
            ${wineNonet}/bin/wine-nonet "$exe"
            echo ""
            echo "After installation, run: pino music-full bridge"
            ;;

          prefix)
            echo "$WINE_PREFIX"
            ;;

          status)
            linux_count=$(find "$LINUX_PLUGINS" -maxdepth 1 \( -name "*.so" -o -name "*.vst3" \) 2>/dev/null | wc -l)
            win_count=$(find "$WIN_PLUGINS" -maxdepth 1 -name "*.dll" 2>/dev/null | wc -l)
            bridged_count=$(find "$BRIDGED_DIR" -maxdepth 1 -name "*.so" 2>/dev/null | wc -l)
            echo "Linux plugins:   $linux_count"
            echo "Windows DLLs:    $win_count"
            echo "Bridged (.so):   $bridged_count"
            echo "Wine prefix:     $WINE_PREFIX"
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
            echo "Usage: pino music-full list|setup|bridge|bridge-add <dir>|install <exe>|install-nonet <exe>|prefix|status|reaper [samples]"
            exit 1
            ;;
        esac
      '';
      fishCompletions = ''
        set -l mf_no_sub 'not __fish_seen_subcommand_from list setup bridge bridge-add install install-nonet prefix status reaper'
        complete -c pino -f -n "__fish_seen_subcommand_from music-full; and $mf_no_sub" -a list           -d 'List available plugins'
        complete -c pino -f -n "__fish_seen_subcommand_from music-full; and $mf_no_sub" -a setup          -d 'Init Wine prefix and yabridge'
        complete -c pino -f -n "__fish_seen_subcommand_from music-full; and $mf_no_sub" -a bridge         -d 'Sync yabridge bridges'
        complete -c pino -f -n "__fish_seen_subcommand_from music-full; and $mf_no_sub" -a bridge-add     -d 'Register a Win plugin directory'
        complete -c pino -f -n "__fish_seen_subcommand_from music-full; and $mf_no_sub" -a install        -d 'Run a Windows plugin installer (with network)'
        complete -c pino -f -n "__fish_seen_subcommand_from music-full; and $mf_no_sub" -a install-nonet  -d 'Run a Windows plugin installer (network blocked)'
        complete -c pino -F -n '__fish_seen_subcommand_from music-full; and __fish_seen_subcommand_from install'
        complete -c pino -F -n '__fish_seen_subcommand_from music-full; and __fish_seen_subcommand_from install-nonet'
        complete -c pino -F -n '__fish_seen_subcommand_from music-full; and __fish_seen_subcommand_from bridge-add'
        complete -c pino -f -n "__fish_seen_subcommand_from music-full; and $mf_no_sub" -a prefix     -d 'Print Wine prefix path'
        complete -c pino -f -n "__fish_seen_subcommand_from music-full; and $mf_no_sub" -a status     -d 'Show plugin counts'
        complete -c pino -f -n "__fish_seen_subcommand_from music-full; and $mf_no_sub" -a reaper     -d 'Launch Reaper (optional: samples for low latency)'
        complete -c pino -f -n '__fish_seen_subcommand_from music-full; and __fish_seen_subcommand_from reaper' -a '64'  -d '64 samples (~1.3ms)'
        complete -c pino -f -n '__fish_seen_subcommand_from music-full; and __fish_seen_subcommand_from reaper' -a '128' -d '128 samples (~2.7ms)'
        complete -c pino -f -n '__fish_seen_subcommand_from music-full; and __fish_seen_subcommand_from reaper' -a '256' -d '256 samples (~5.3ms)'
      '';
    };
  };
}
