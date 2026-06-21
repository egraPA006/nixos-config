{ hostname, lib, pkgs, ... }:
{
  home.activation = lib.mkIf (hostname == "re-1") (
    let
      singleProfile = pkgs.writeText "single.json" (builtins.toJSON {
        name = "single";
        logical_monitors = [{
          x = 0; y = 0; scale = 1.0; transform = 0; primary = true;
          monitors = [{ connector = "DP-3"; width = 2560; height = 1440; refresh = 59.951; }];
        }];
      });
      dualProfile = pkgs.writeText "dual.json" (builtins.toJSON {
        name = "dual";
        logical_monitors = [
          {
            x = 0; y = 0; scale = 1.0; transform = 0; primary = true;
            monitors = [{ connector = "DP-3"; width = 2560; height = 1440; refresh = 59.951; }];
          }
          {
            x = 2560; y = 234; scale = 1.0; transform = 0; primary = false;
            monitors = [{ connector = "HDMI-1"; width = 1920; height = 1080; refresh = 60.0; }];
          }
        ];
      });
    in {
      monitorProfiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/monitor-profiles"
        [[ -f "$HOME/.config/monitor-profiles/single.json" ]] || \
          ${pkgs.coreutils}/bin/cp ${singleProfile} "$HOME/.config/monitor-profiles/single.json"
        [[ -f "$HOME/.config/monitor-profiles/dual.json" ]] || \
          ${pkgs.coreutils}/bin/cp ${dualProfile} "$HOME/.config/monitor-profiles/dual.json"
      '';
    }
  );

  xdg.configFile."monitors.xml" = lib.mkIf (hostname == "re-1") {
    force = true;
    text = ''
      <monitors version="2">
        <configuration>
          <layoutmode>logical</layoutmode>
          <logicalmonitor>
            <x>0</x>
            <y>0</y>
            <scale>1</scale>
            <primary>yes</primary>
            <monitor>
              <monitorspec>
                <connector>DP-3</connector>
                <vendor>HPN</vendor>
                <product>HP X27q</product>
                <serial>6CM14208Y0</serial>
              </monitorspec>
              <mode>
                <width>2560</width>
                <height>1440</height>
                <rate>59.951</rate>
              </mode>
            </monitor>
          </logicalmonitor>
          <logicalmonitor>
            <x>2560</x>
            <y>234</y>
            <scale>1</scale>
            <monitor>
              <monitorspec>
                <connector>HDMI-1</connector>
                <vendor>SAM</vendor>
                <product>SAMSUNG</product>
                <serial>0x01000e00</serial>
              </monitorspec>
              <mode>
                <width>1920</width>
                <height>1080</height>
                <rate>60.000</rate>
              </mode>
            </monitor>
          </logicalmonitor>
        </configuration>
      </monitors>
    '';
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http"   = "chromium-browser.desktop";
      "x-scheme-handler/https"  = "chromium-browser.desktop";
      "text/html"               = "chromium-browser.desktop";
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
      accent-color = "pink";
    };

    "org/gnome/desktop/background" = {
      picture-uri = "file:///home/egrapa/nixos-config/home/wallpaper-${hostname}.jpg";
      picture-uri-dark = "file:///home/egrapa/nixos-config/home/wallpaper-${hostname}.jpg";
      picture-options = "zoom";
    };

    "org/gnome/shell" = {
      favorite-apps = [
        "org.gnome.Console.desktop"
        "chromium-browser.desktop"
        "org.gnome.Nautilus.desktop"
        "org.telegram.desktop.desktop"
      ];
      enabled-extensions = [
        "clipboard-history@alexsaveau.dev"
        "tiling-assistant@leleat-on-github"
      ];
    };
  };
}
