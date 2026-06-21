{ hostname, lib, pkgs, ... }:
let
  monitorTvExt = "monitor-tv@re-1";
  python3      = "${pkgs.python3.withPackages (ps: [ ps.pygobject3 ])}/bin/python3";
in
{
  # Quick Settings toggle: single monitor (DP-3) or + TV (HDMI-1).
  # Uses a Python subprocess for all D-Bus work so the shell never blocks.
  xdg.dataFile."gnome-shell/extensions/${monitorTvExt}/metadata.json".text =
    builtins.toJSON {
      name        = "Monitor TV switch";
      description = "Quick Settings toggle between single monitor and + TV";
      uuid        = monitorTvExt;
      "shell-version" = [ "45" "46" "47" "48" "49" "50" ];
      version     = 1;
    };

  # switch.py – called by the extension; handles Mutter DisplayConfig D-Bus.
  xdg.dataFile."gnome-shell/extensions/${monitorTvExt}/switch.py".text = ''
    #!/usr/bin/env python3
    """Usage: switch.py [status|single|dual]"""
    import sys
    import gi
    gi.require_version('Gio', '2.0')
    gi.require_version('GLib', '2.0')
    from gi.repository import Gio, GLib

    DEST  = 'org.gnome.Mutter.DisplayConfig'
    PATH  = '/org/gnome/Mutter/DisplayConfig'
    IFACE = 'org.gnome.Mutter.DisplayConfig'
    DP3   = 'DP-3'
    HDMI  = 'HDMI-1'

    def proxy():
        return Gio.DBusProxy.new_for_bus_sync(
            Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None,
            DEST, PATH, IFACE, None)

    def call(p, method, args=None):
        return p.call_sync(method, args, Gio.DBusCallFlags.NONE, -1, None)

    def find_mode(result, conn, w, h, r):
        mons = result.get_child_value(1)
        for i in range(mons.n_children()):
            mon  = mons.get_child_value(i)
            spec = mon.get_child_value(0)
            if spec.get_child_value(0).get_string() != conn:
                continue
            modes = mon.get_child_value(1)
            for j in range(modes.n_children()):
                m = modes.get_child_value(j)
                if (m.get_child_value(1).get_int32()    == w and
                    m.get_child_value(2).get_int32()    == h and
                    abs(m.get_child_value(3).get_double() - r) < 1.0):
                    return m.get_child_value(0).get_string()
        return None

    def hdmi_active(result):
        lms = result.get_child_value(2)
        for i in range(lms.n_children()):
            lm   = lms.get_child_value(i)
            mons = lm.get_child_value(5)
            for j in range(mons.n_children()):
                if mons.get_child_value(j).get_child_value(0).get_string() == HDMI:
                    return True
        return False

    action = sys.argv[1] if len(sys.argv) > 1 else 'status'
    p      = proxy()
    state  = call(p, 'GetCurrentState')

    if action == 'status':
        print('on' if hdmi_active(state) else 'off')
        sys.exit(0)

    serial   = state.get_child_value(0).get_uint32()
    dp3_mode = find_mode(state, DP3, 2560, 1440, 59.951)
    if not dp3_mode:
        print('DP-3 mode not found', file=sys.stderr)
        sys.exit(1)

    logmons = [(0, 0, 1.0, 0, True, [(DP3, dp3_mode, {})])]
    if action == 'dual':
        hdmi_mode = find_mode(state, HDMI, 1920, 1080, 60.0)
        if hdmi_mode:
            logmons.append((2560, 234, 1.0, 0, False, [(HDMI, hdmi_mode, {})]))

    call(p, 'ApplyMonitorsConfig',
         GLib.Variant('(uua(iiduba(ssa{sv}))a{sv})', (serial, 2, logmons, {})))
  '';

  xdg.dataFile."gnome-shell/extensions/${monitorTvExt}/extension.js".text = ''
    import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
    import { QuickToggle, SystemIndicator } from 'resource:///org/gnome/shell/ui/quickSettings.js';
    import * as Main from 'resource:///org/gnome/shell/ui/main.js';
    import Gio from 'gi://Gio';
    import GObject from 'gi://GObject';

    const PYTHON3 = '${python3}';

    const TVToggle = GObject.registerClass(
    class TVToggle extends QuickToggle {
        _init() {
            super._init({ title: 'TV', iconName: 'video-display-symbolic' });
        }
    });

    const TVIndicator = GObject.registerClass(
    class TVIndicator extends SystemIndicator {
        _init(script) {
            super._init();
            this._script  = script;
            this._syncing = false; // guard: don't react to programmatic checked changes
            this._toggle  = new TVToggle();
            // notify::checked fires AFTER checked is updated — always has the new value.
            // Use it instead of 'clicked' to avoid timing ambiguity.
            this._toggle.connect('notify::checked', () => {
                if (this._syncing) return;
                this._run([this._toggle.checked ? 'dual' : 'single']);
            });
            this.quickSettingsItems.push(this._toggle);
            this._syncState();
        }

        _run(args, onStdout) {
            try {
                const flags = onStdout
                    ? Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE
                    : Gio.SubprocessFlags.STDERR_SILENCE;
                const proc = Gio.Subprocess.new([PYTHON3, this._script, ...args], flags);
                if (onStdout) {
                    proc.communicate_utf8_async(null, null, (_p, res) => {
                        try {
                            const [, out] = _p.communicate_utf8_finish(res);
                            onStdout(out.trim());
                        } catch (e) { console.error('monitor-tv:', e.message); }
                    });
                }
            } catch (e) { console.error('monitor-tv run:', e.message); }
        }

        _syncState() {
            this._run(['status'], out => {
                this._syncing = true;
                this._toggle.checked = out === 'on';
                this._syncing = false;
            });
        }

        destroy() {
            this._toggle?.destroy();
            this.quickSettingsItems = [];
            super.destroy();
        }
    });

    export default class MonitorTVExtension extends Extension {
        enable() {
            this._indicator = new TVIndicator(this.path + '/switch.py');
            Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
        }
        disable() {
            this._indicator?.destroy();
            this._indicator = null;
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
        monitorTvExt
      ];
    };
  };
}
