# Guitar Pro uses its own Wine prefix and saved installer directory.
{ config, lib, pkgs, ... }:
let
  cfg = config.pino.profiles.guitarPro;
  user = config.pino.user;
  installersDir = "${cfg.localDir}/installs";
  programDir = "${cfg.localDir}/program";
  soundbanksDir = "${cfg.localDir}/soundbanks";
  wine = pkgs.wineWow64Packages.stable;
  guitarPro = pkgs.writeShellScriptBin "guitar-pro" ''
    export WINEPREFIX=${lib.escapeShellArg cfg.winePrefix}
    program=${lib.escapeShellArg "${programDir}/GuitarPro.exe"}
    if [ ! -f "$program" ]; then
      echo "Guitar Pro is not installed in $WINEPREFIX; run: pino desktop guitar-pro install" >&2
      exit 1
    fi
    exec ${wine}/bin/wine "$program" "$@"
  '';
in
{
  environment.systemPackages = [ wine guitarPro ];

  systemd.tmpfiles.rules = [
    "d ${cfg.localDir} 0755 ${user.name} users -"
    "d ${installersDir} 0755 ${user.name} users -"
  ];

  home-manager.users.${user.name}.xdg.desktopEntries.guitar-pro = {
    name = "Guitar Pro 8";
    exec = "${guitarPro}/bin/guitar-pro %F";
    icon = "guitar-pro";
    categories = [ "Audio" "AudioVideo" ];
    mimeType = [ "application/x-guitar-pro" ];
  };

  pino.subcommands.desktop.commands."guitar-pro" = {
    description = "Guitar Pro 8 in its own Wine prefix";
    commands = {
      install = { description = "Install Guitar Pro from a saved EXE"; usage = "[file.exe]"; };
      deps.description = "Install bundled Visual C++ runtimes into the Wine prefix";
      run = { description = "Launch Guitar Pro"; usage = "[file.gp]"; };
      status.description = "Show installer and installed program state";
      prefix.description = "Print the Wine prefix path";
    };
    helpText = ''
      Put the complete Guitar Pro 8 installer in ${installersDir}, then run
      `pino desktop guitar-pro install`. The app and soundbanks are extracted
      to ${cfg.localDir}; Wine settings live in ${cfg.winePrefix}.
    '';
    script = ''
      export WINEPREFIX=${lib.escapeShellArg cfg.winePrefix}
      INSTALLERS=${lib.escapeShellArg installersDir}
      PROGRAM=${lib.escapeShellArg programDir}
      SOUNDBANKS=${lib.escapeShellArg soundbanksDir}
      BANK_LINK="$WINEPREFIX/drive_c/ProgramData/Arobas Music/Soundbanks"

      link_soundbanks() {
        mkdir -p "$(dirname "$BANK_LINK")" || return 1
        if [ -L "$BANK_LINK" ] && [ "$(readlink "$BANK_LINK")" = "$SOUNDBANKS" ]; then
          return 0
        fi
        [ ! -e "$BANK_LINK" ] && [ ! -L "$BANK_LINK" ] || {
          echo "Soundbank destination already exists: $BANK_LINK" >&2
          return 1
        }
        ln -s "$SOUNDBANKS" "$BANK_LINK"
      }

      install_deps() {
        local installer="$1" work runtime
        [ -f "$WINEPREFIX/.guitar-pro-vcrun-ready" ] && return 0
        mkdir -p "$WINEPREFIX" || return 1
        ${wine}/bin/wineboot --init || return 1
        work=$(mktemp -d -p ${lib.escapeShellArg cfg.localDir} .guitar-pro-deps.XXXXXX) || return 1
        ${pkgs.innoextract}/bin/innoextract --extract --silent \
          --include 'tmp/120/vcredist_x64.exe' --include 'tmp/142/vcredist_x64.exe' \
          --output-dir "$work" "$installer" || { rm -rf "$work"; return 1; }
        for runtime in 120 142; do
          ${pkgs.coreutils}/bin/timeout 120 ${wine}/bin/wine \
            "$work/tmp/$runtime/vcredist_x64.exe" /quiet /norestart || { rm -rf "$work"; return 1; }
          ${pkgs.coreutils}/bin/timeout 30 ${wine}/bin/wineserver -w || { rm -rf "$work"; return 1; }
        done
        rm -rf "$work"
        touch "$WINEPREFIX/.guitar-pro-vcrun-ready"
      }

      case "''${1:-}" in
        install)
          installer="''${2:-}"
          if [ -z "$installer" ]; then
            shopt -s nullglob
            installers=("$INSTALLERS"/*.exe)
            [ "''${#installers[@]}" -eq 1 ] || {
              echo "Expected one complete .exe in $INSTALLERS; pass a filename if there are several" >&2
              exit 1
            }
            installer="''${installers[0]}"
          elif [ ! -f "$installer" ]; then
            installer="$INSTALLERS/$installer"
          fi
          [ -f "$installer" ] && [[ "$installer" == *.exe ]] || {
            echo "Installer not found: $installer" >&2
            exit 1
          }
          if [ -f "$PROGRAM/GuitarPro.exe" ] && [ -d "$SOUNDBANKS/com.arobas-music.soundbank.standard" ]; then
            link_soundbanks || exit 1
            install_deps "$installer" || exit 1
            echo "Guitar Pro files already installed"
            exit 0
          fi
          [ ! -e "$PROGRAM" ] && [ ! -e "$SOUNDBANKS" ] || {
            echo "Partial Guitar Pro installation in ${cfg.localDir}; inspect it before retrying" >&2
            exit 1
          }
          mkdir -p ${lib.escapeShellArg cfg.localDir} || exit 1
          work=$(mktemp -d -p ${lib.escapeShellArg cfg.localDir} .guitar-pro-install.XXXXXX) || exit 1
          trap 'rm -rf "$work"' EXIT
          ${pkgs.innoextract}/bin/innoextract --extract --silent --output-dir "$work/main" "$installer" || exit 1
          [ -f "$work/main/app/GuitarPro.exe" ] && [ -f "$work/main/tmp/soundbank-full.exe" ] || {
            echo "Guitar Pro installer contents changed" >&2
            exit 1
          }
          ${pkgs.innoextract}/bin/innoextract --extract --silent --output-dir "$work/bank" \
            "$work/main/tmp/soundbank-full.exe" || exit 1
          bank_source="$work/bank/commonappdata/Arobas Music/Soundbanks"
          [ -d "$bank_source/com.arobas-music.soundbank.standard" ] || {
            echo "Guitar Pro soundbank contents changed" >&2
            exit 1
          }
          mv "$work/main/app" "$PROGRAM" || exit 1
          mv "$bank_source" "$SOUNDBANKS" || exit 1
          link_soundbanks || exit 1
          install_deps "$installer" || exit 1
          echo "Guitar Pro files installed in $PROGRAM and $SOUNDBANKS"
          ;;
        deps)
          installer="$INSTALLERS/guitar-pro-8-setup.exe"
          [ -f "$installer" ] || { echo "Installer not found: $installer" >&2; exit 1; }
          install_deps "$installer"
          ;;
        run)
          shift
          ${guitarPro}/bin/guitar-pro "$@"
          ;;
        status)
          if [ -f "$PROGRAM/GuitarPro.exe" ] && [ -d "$SOUNDBANKS/com.arobas-music.soundbank.standard" ]; then
            echo "Guitar Pro files: installed"
          else
            echo "Guitar Pro files: not installed"
          fi
          echo "Installers: $INSTALLERS"
          echo "Program: $PROGRAM"
          echo "Soundbanks: $SOUNDBANKS"
          echo "Wine prefix: $WINEPREFIX"
          [ -f "$WINEPREFIX/.guitar-pro-vcrun-ready" ] && echo "Visual C++ runtimes: installed" || echo "Visual C++ runtimes: missing"
          ;;
        prefix)
          echo "$WINEPREFIX"
          ;;
        *)
          echo "Usage: pino desktop guitar-pro install [file.exe]|deps|run [file.gp]|status|prefix" >&2
          exit 1
          ;;
      esac
    '';
  };
}
