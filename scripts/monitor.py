"""monitor — save and switch GNOME display profiles via Mutter DisplayConfig."""
import sys, json, gi
gi.require_version('Gio', '2.0')
gi.require_version('GLib', '2.0')
from gi.repository import Gio, GLib
from pathlib import Path

PROFILES_DIR = Path.home() / '.config' / 'monitor-profiles'
DEST  = 'org.gnome.Mutter.DisplayConfig'
PATH  = '/org/gnome/Mutter/DisplayConfig'
IFACE = 'org.gnome.Mutter.DisplayConfig'

# ── D-Bus helpers ─────────────────────────────────────────────────────────────

def proxy():
    return Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None,
        DEST, PATH, IFACE, None)

def get_state(p):
    return p.call_sync('GetCurrentState', None, Gio.DBusCallFlags.NONE, -1, None)

# ── Parsing GetCurrentState ───────────────────────────────────────────────────

def _bool_prop(props_v, key):
    for i in range(props_v.n_children()):
        kv = props_v.get_child_value(i)
        if kv.get_child_value(0).get_string() == key:
            return kv.get_child_value(1).get_child_value(0).get_boolean()
    return False

def physical_monitors(state):
    """connector → [(mode_id, w, h, refresh, is_current)]"""
    mons = state.get_child_value(1)
    out  = {}
    for i in range(mons.n_children()):
        mon  = mons.get_child_value(i)
        conn = mon.get_child_value(0).get_child_value(0).get_string()
        modes_v = mon.get_child_value(1)
        out[conn] = []
        for j in range(modes_v.n_children()):
            m   = modes_v.get_child_value(j)
            mid = m.get_child_value(0).get_string()
            w   = m.get_child_value(1).get_int32()
            h   = m.get_child_value(2).get_int32()
            r   = m.get_child_value(3).get_double()
            cur = _bool_prop(m.get_child_value(6), 'is-current')
            out[conn].append((mid, w, h, r, cur))
    return out

def logical_monitors(state, phys):
    """List of dicts matching the JSON profile format."""
    lms = state.get_child_value(2)
    out = []
    for i in range(lms.n_children()):
        lm      = lms.get_child_value(i)
        x       = lm.get_child_value(0).get_int32()
        y       = lm.get_child_value(1).get_int32()
        scale   = lm.get_child_value(2).get_double()
        xform   = lm.get_child_value(3).get_uint32()
        primary = lm.get_child_value(4).get_boolean()
        mons_v  = lm.get_child_value(5)   # a(ssss) connector/vendor/product/serial
        monitors = []
        for j in range(mons_v.n_children()):
            conn = mons_v.get_child_value(j).get_child_value(0).get_string()
            # find current mode for this connector
            for (_, w, h, r, cur) in phys.get(conn, []):
                if cur:
                    monitors.append({'connector': conn,
                                     'width': w, 'height': h,
                                     'refresh': round(r, 3)})
                    break
        if monitors:
            out.append({'x': x, 'y': y, 'scale': scale,
                        'transform': xform, 'primary': primary,
                        'monitors': monitors})
    return out

# ── Applying a profile ────────────────────────────────────────────────────────

def find_mode(phys, conn, w, h, r):
    for (mid, mw, mh, mr, _) in phys.get(conn, []):
        if mw == w and mh == h and abs(mr - r) < 1.0:
            return mid
    return None

def apply(p, profile):
    state  = get_state(p)
    serial = state.get_child_value(0).get_uint32()
    phys   = physical_monitors(state)
    logmons = []
    for lm in profile['logical_monitors']:
        mons_in = []
        for m in lm['monitors']:
            mid = find_mode(phys, m['connector'], m['width'], m['height'], m['refresh'])
            if not mid:
                sys.exit(f"error: no mode for {m['connector']} "
                         f"{m['width']}x{m['height']}@{m['refresh']} "
                         f"(monitor not connected?)")
            mons_in.append((m['connector'], mid, {}))
        logmons.append((int(lm['x']), int(lm['y']), float(lm['scale']),
                        int(lm['transform']), bool(lm['primary']), mons_in))
    p.call_sync(
        'ApplyMonitorsConfig',
        GLib.Variant('(uua(iiduba(ssa{sv}))a{sv})', (serial, 2, logmons, {})),
        Gio.DBusCallFlags.NONE, -1, None)

# ── Commands ──────────────────────────────────────────────────────────────────

def cmd_save(name):
    p     = proxy()
    state = get_state(p)
    phys  = physical_monitors(state)
    prof  = {'name': name, 'logical_monitors': logical_monitors(state, phys)}
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    (PROFILES_DIR / f'{name}.json').write_text(json.dumps(prof, indent=2))
    n = len(prof['logical_monitors'])
    print(f"Saved '{name}' ({n} logical monitor{'s' if n != 1 else ''})")

def cmd_switch(name):
    path = PROFILES_DIR / f'{name}.json'
    if not path.exists():
        sys.exit(f"Profile '{name}' not found — use 'monitor list'")
    apply(proxy(), json.loads(path.read_text()))
    print(f"Switched to '{name}'")

def cmd_list():
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    files = sorted(PROFILES_DIR.glob('*.json'))
    if not files:
        print("No profiles yet.  Use: monitor save <name>")
        return
    for f in files:
        try:
            d    = json.loads(f.read_text())
            desc = ', '.join(
                f"{m['connector']} {m['width']}x{m['height']}@{m['refresh']}Hz"
                for lm in d.get('logical_monitors', [])
                for m  in lm.get('monitors', []))
            print(f"  {f.stem:<20}  {desc}")
        except Exception:
            print(f"  {f.stem}")

def cmd_status():
    state = get_state(proxy())
    phys  = physical_monitors(state)
    lms   = logical_monitors(state, phys)
    print("Current layout:")
    for lm in lms:
        tag = " [primary]" if lm['primary'] else ""
        for m in lm['monitors']:
            print(f"  {m['connector']:<10} {m['width']}x{m['height']}@{m['refresh']}Hz"
                  f"  pos={lm['x']},{lm['y']}  scale={lm['scale']}{tag}")

# ── Entry point ───────────────────────────────────────────────────────────────

def usage():
    print("Usage: monitor <command> [name]")
    print()
    print("  list              List saved profiles")
    print("  switch <name>     Apply a saved profile")
    print("  save <name>       Save current layout as a profile")
    print("  status            Show current layout")

cmd  = sys.argv[1] if len(sys.argv) > 1 else ''
name = sys.argv[2] if len(sys.argv) > 2 else ''

if   cmd == 'save'   and name: cmd_save(name)
elif cmd == 'switch' and name: cmd_switch(name)
elif cmd == 'list':            cmd_list()
elif cmd == 'status':          cmd_status()
else:                          usage(); sys.exit(0 if not cmd else 1)
