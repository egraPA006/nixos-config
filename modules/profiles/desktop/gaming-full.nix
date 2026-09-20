{ config, pkgs, ... }:

{
  imports = [ ./gaming-lite.nix ];

  services.udev.packages = [ pkgs.boxflat ];

  home-manager.users.${config.pino.user.name} = { lib, ... }: {
    home.activation.boxflatRulesVersion = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="$HOME/.config/boxflat/settings.yml"
      ${pkgs.coreutils}/bin/mkdir -p -m 0700 "$HOME/.config/boxflat"
      if [ -f "$settings" ]; then
        if ${pkgs.gnugrep}/bin/grep -q '^rules-version:' "$settings"; then
          ${pkgs.gnused}/bin/sed -i 's/^rules-version:.*/rules-version: 2/' "$settings"
        else
          printf '\nrules-version: 2\n' >> "$settings"
        fi
      else
        printf 'rules-version: 2\n' | ${pkgs.coreutils}/bin/install -m 0600 /dev/stdin "$settings"
      fi
    '';
  };
  programs.gamescope = {
    capSysNice = true;
  };

  programs.steam = {
    remotePlay.openFirewall = true;
    gamescopeSession = {
      args = [
        "--force-grab-cursor"
      ];
    };
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
    package = pkgs.steam.override {
      extraProfile = ''
        export PROTON_ENABLE_WAYLAND=1
      '';
    };
  };

  programs.gamemode = {
    enableRenice = true;
  };

  environment.systemPackages = with pkgs; [
    gamescope-wsi
    lutris
    r2modman
    # wineWowPackages.stable
    # winetricks
    boxflat
  ];
}
