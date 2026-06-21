{ hostname, lib, ... }:
let
  lockPanelExt = "hide-lock-panel@local";
in
{
  # Minimal GNOME Shell extension: hides the top panel while the lock screen
  # is active so Quick Settings (WiFi, BT, etc.) are not reachable without
  # first unlocking. Volume media keys still work without the panel.
  xdg.dataFile."gnome-shell/extensions/${lockPanelExt}/metadata.json".text =
    builtins.toJSON {
      name        = "Hide panel on lock screen";
      description = "Hides the system panel while the screen is locked";
      uuid        = lockPanelExt;
      "shell-version" = [ "45" "46" "47" "48" "49" "50" ];
      version     = 1;
    };

  xdg.dataFile."gnome-shell/extensions/${lockPanelExt}/extension.js".text = ''
    import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
    import * as Main from 'resource:///org/gnome/shell/ui/main.js';

    export default class HideLockPanel extends Extension {
      enable() {
        this._id = Main.screenShield.connect('active-changed', () => this._sync());
        this._sync();
      }
      disable() {
        if (this._id) {
          Main.screenShield.disconnect(this._id);
          this._id = null;
        }
        this._setQsVisible(true);
      }
      _setQsVisible(visible) {
        const qs = Main.panel.statusArea.quickSettings;
        if (qs) qs.visible = visible;
      }
      _sync() {
        this._setQsVisible(!Main.screenShield.active);
      }
    }
  '';
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
        lockPanelExt
      ];
    };
  };
}
