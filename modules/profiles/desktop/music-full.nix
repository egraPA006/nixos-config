# Full music production: Reaper DAW + yabridge for Windows VST/VST3 plugins.

# Windows plugins: place DLLs in data/music-full/plugins/win (repo) — they sync to
# localDir/plugins/win and are bridged via yabridge into localDir/plugins/linux-bridged.
# Linux plugins: place .so files in data/music-full/plugins/linux — they sync to
# localDir/plugins/linux.
# Wine prefix is configured by pino.profiles.musicFull.winePrefix.
{ config, lib, pkgs, ... }:
let
  cfg       = config.pino.profiles.musicFull;
  configDir = config.pino.configDir;
  user = config.pino.user;
  srcDir    = "${configDir}/data/music-full";

  wineNonet = pkgs.writeShellScriptBin "wine-nonet" ''
    exec ${pkgs.util-linux}/bin/unshare \
      --user --map-user="$(id -u)" --map-group="$(id -g)" \
      --net \
      ${pkgs.wineWow64Packages.stable}/bin/wine64 "$@"
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
        chown -R ${lib.escapeShellArg user.name}:users "${cfg.localDir}"

        yabridgectl_cfg="${user.home}/.config/yabridgectl/config.toml"
        mkdir -p "$(dirname "$yabridgectl_cfg")"
        if ! grep -qF "${cfg.localDir}/plugins/win" "$yabridgectl_cfg" 2>/dev/null; then
          printf '\n[[directories]]\npath = "%s"\n' "${cfg.localDir}/plugins/win" >> "$yabridgectl_cfg"
        fi
        chown -R ${lib.escapeShellArg user.name}:users "${user.home}/.config/yabridgectl"

        yabridge_cfg="${user.home}/.config/yabridge/config.toml"
        mkdir -p "$(dirname "$yabridge_cfg")"
        printf '[yabridge]\nwine-binary = "%s"\n' "${wineNonet}/bin/wine-nonet" > "$yabridge_cfg"
        chown -R ${lib.escapeShellArg user.name}:users "${user.home}/.config/yabridge"
      else
        echo "music-full-sync: $parent not available, skipping" >&2
      fi
    '';

    pino.subcommands.desktop.commands."music-full" = {
      description = "Reaper + yabridge Windows VST bridge + plugin management";
      commands = {
        list.description = "List Linux and bridged Windows plugins";
        setup.description = "Initialize Wine and yabridge";
        bridge.description = "Synchronize yabridge plugins";
        bridge-add = { description = "Register a Windows plugin directory"; usage = "<directory>"; };
        install = { description = "Run a Windows plugin installer"; usage = "<exe>"; };
        install-nonet = { description = "Run an installer without network"; usage = "<exe>"; };
        prefix.description = "Print the Wine prefix path";
        status.description = "Show plugin counts";
        reaper = { description = "Launch Reaper"; usage = "[samples]"; };
      };
      helpText = ''
        pino desktop music-full — manage full music production setup
          pino desktop music-full list              List Linux and bridged Windows plugins
          pino desktop music-full setup             Init Wine prefix and configure yabridge
          pino desktop music-full bridge            Sync yabridge (update .so bridges for Win plugins)
          pino desktop music-full bridge-add <dir>  Register a Win plugin directory with yabridge
          pino desktop music-full install <exe>        Run a Windows plugin installer (with network)
          pino desktop music-full install-nonet <exe>  Run a Windows plugin installer (network blocked)
          pino desktop music-full reaper [samples]  Launch Reaper (with optional PIPEWIRE_LATENCY, e.g. 128)
          pino desktop music-full prefix            Print Wine prefix path
          pino desktop music-full status            Show plugin counts

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
            [ "$count" = 0 ] && echo "  (none — run 'pino desktop music-full bridge' after installing Win plugins)"
            ;;

          setup)
            echo "Initializing Wine prefix: $WINE_PREFIX"
            mkdir -p "$WINE_PREFIX"
            ${pkgs.wineWow64Packages.stable}/bin/wineboot --init
            echo ""
            echo "Installing Windows runtimes..."
            ${pkgs.winetricks}/bin/winetricks -q mfc42
            echo ""
            echo "Configuring yabridge output dir: $BRIDGED_DIR"
            mkdir -p "$BRIDGED_DIR"
            ${pkgs.yabridgectl}/bin/yabridgectl add "$WIN_PLUGINS"
            echo ""
            echo "Done. Install Windows plugins with:"
            echo "  pino desktop music-full install <Installer.exe>"
            echo "Then run: pino desktop music-full bridge"
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
            [ -z "$dir" ] && { echo "Usage: pino desktop music-full bridge-add <directory>"; exit 1; }
            ${pkgs.yabridgectl}/bin/yabridgectl add "$dir"
            echo "Added. Run 'pino desktop music-full bridge' to create .so files."
            ;;

          install)
            exe="''${2:-}"
            [ -z "$exe" ] && { echo "Usage: pino desktop music-full install <Installer.exe>"; exit 1; }
            [ ! -f "$exe" ] && { echo "File not found: $exe"; exit 1; }
            echo "Running installer in Wine prefix: $WINE_PREFIX"
            ${pkgs.wineWow64Packages.stable}/bin/wine "$exe"
            echo ""
            echo "After installation, run: pino desktop music-full bridge"
            ;;

          install-nonet)
            exe="''${2:-}"
            [ -z "$exe" ] && { echo "Usage: pino desktop music-full install-nonet <Installer.exe>"; exit 1; }
            [ ! -f "$exe" ] && { echo "File not found: $exe"; exit 1; }
            echo "Running installer in Wine prefix: $WINE_PREFIX (network blocked)"
            ${wineNonet}/bin/wine-nonet "$exe"
            echo ""
            echo "After installation, run: pino desktop music-full bridge"
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
            echo "Usage: pino desktop music-full list|setup|bridge|bridge-add <dir>|install <exe>|install-nonet <exe>|prefix|status|reaper [samples]"
            exit 1
            ;;
        esac
      '';
      fishCompletions = ''
        complete -c pino -F -n '__fish_pino_at_path desktop music-full install'
        complete -c pino -F -n '__fish_pino_at_path desktop music-full install-nonet'
        complete -c pino -F -n '__fish_pino_at_path desktop music-full bridge-add'
        complete -c pino -f -n '__fish_pino_at_path desktop music-full reaper' \
          -a '64 128 256' -d 'PipeWire latency samples'
      '';
    };
  };
}
