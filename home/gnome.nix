{ hostname, lib, ... }:
let
  lockPanelExt = "hide-lock-panel@local";
  monitorTvExt = "monitor-tv@re-1";
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

  # Quick Settings toggle: single monitor (DP-3 only) or + TV (HDMI-1).
  # Positions match monitors.xml. Uses Mutter DisplayConfig D-Bus directly.
  xdg.dataFile."gnome-shell/extensions/${monitorTvExt}/metadata.json".text =
    builtins.toJSON {
      name        = "Monitor TV switch";
      description = "Quick Settings toggle between single monitor and + TV";
      uuid        = monitorTvExt;
      "shell-version" = [ "45" "46" "47" "48" "49" "50" ];
      version     = 1;
    };

  xdg.dataFile."gnome-shell/extensions/${monitorTvExt}/extension.js".text = ''
    import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
    import { QuickToggle, SystemIndicator } from 'resource:///org/gnome/shell/ui/quickSettings.js';
    import * as Main from 'resource:///org/gnome/shell/ui/main.js';
    import Gio from 'gi://Gio';
    import GLib from 'gi://GLib';
    import GObject from 'gi://GObject';

    const DC_DEST  = 'org.gnome.Mutter.DisplayConfig';
    const DC_PATH  = '/org/gnome/Mutter/DisplayConfig';
    const DC_IFACE = 'org.gnome.Mutter.DisplayConfig';
    const PERSIST  = 2; // persistent config

    // Matches monitors.xml
    const DP3  = { conn: 'DP-3',   w: 2560, h: 1440, r: 59.951, x: 0,    y: 0,   primary: true  };
    const HDMI = { conn: 'HDMI-1', w: 1920, h: 1080, r: 60.0,   x: 2560, y: 234, primary: false };

    const TVToggle = GObject.registerClass(
    class TVToggle extends QuickToggle {
        _init() {
            super._init({ title: 'TV', iconName: 'video-display-symbolic' });
        }
    });

    const TVIndicator = GObject.registerClass(
    class TVIndicator extends SystemIndicator {
        _init() {
            super._init();
            this._proxy = Gio.DBusProxy.new_for_bus_sync(
                Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, null,
                DC_DEST, DC_PATH, DC_IFACE, null);
            this._toggle = new TVToggle();
            this._toggle.connect('clicked', () => this._onToggle());
            this.quickSettingsItems.push(this._toggle);
            this._syncState();
        }

        _state() {
            return this._proxy
                .call_sync('GetCurrentState', null, Gio.DBusCallFlags.NONE, -1, null)
                .recursiveUnpack();
        }

        // monitors is a((ssss)a(siiddada{sv})a{sv}) after recursiveUnpack:
        // [ [[connector,vendor,product,sn], [modes...], props], ... ]
        _findMode(monitors, target) {
            for (const [[connector], modes] of monitors) {
                if (connector !== target.conn) continue;
                for (const [modeId, w, h, r] of modes)
                    if (w === target.w && h === target.h && Math.abs(r - target.r) < 1.0)
                        return modeId;
            }
            return null;
        }

        _syncState() {
            try {
                const [,, logMons] = this._state();
                // logMons: a(iiduba(ssa{sv})a{sv})
                // each: [x, y, scale, transform, primary, [[conn, modeId, props],...], props]
                this._toggle.checked = logMons.some(([,,,,,mons]) =>
                    mons.some(([c]) => c === HDMI.conn));
            } catch (e) {
                console.error('monitor-tv syncState:', e.message);
            }
        }

        _onToggle() {
            try {
                const [serial, monitors] = this._state();
                const dp3Mode = this._findMode(monitors, DP3);
                if (!dp3Mode) { console.error('monitor-tv: DP-3 mode not found'); return; }

                const logMons = [
                    [DP3.x, DP3.y, 1.0, 0, DP3.primary, [[DP3.conn, dp3Mode, {}]]],
                ];
                if (this._toggle.checked) {
                    const hdmiMode = this._findMode(monitors, HDMI);
                    if (hdmiMode)
                        logMons.push([HDMI.x, HDMI.y, 1.0, 0, HDMI.primary, [[HDMI.conn, hdmiMode, {}]]]);
                }

                this._proxy.call_sync(
                    'ApplyMonitorsConfig',
                    new GLib.Variant('(uua(iiduba(ssa{sv}))a{sv})', [serial, PERSIST, logMons, {}]),
                    Gio.DBusCallFlags.NONE, -1, null);
            } catch (e) {
                console.error('monitor-tv toggle:', e.message);
            }
        }

        destroy() {
            this._toggle?.destroy();
            this.quickSettingsItems = [];
            super.destroy();
        }
    });

    export default class MonitorTVExtension extends Extension {
        enable() {
            this._indicator = new TVIndicator();
            Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
        }
        disable() {
            this._indicator?.destroy();
            this._indicator = null;
        }
    }
  '';

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
        monitorTvExt
      ];
    };
  };
}
