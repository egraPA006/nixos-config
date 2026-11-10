#!/usr/bin/env python3
"""System tunnel supervisor and application routing for Pino desktops."""
import argparse
import copy
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import time

STATE = Path("/var/lib/pino/tunnel")
RUNTIME = Path("/run/pino-tunnel")
SERVICE = "pino-tunnel.service"
DIRECT_MARK = 2024
VPN_MARK = 2025


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True)


def write_json(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_suffix(".new")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(path)


def read_policy():
    path = STATE / "split.json"
    return json.loads(path.read_text()) if path.exists() else {"default": "vpn", "apps": {}}


def app_rule(application, outbound):
    if application.startswith("/"):
        return {"process_path": [application], "action": "route", "outbound": outbound}
    # Nix wrappers commonly exec a hidden binary with a -wrapped suffix.
    return {"process_path_regex": [r"/(?:\.)?" + re.escape(application) + r"(?:-wrapped)?$"],
            "action": "route", "outbound": outbound}


def router_config(kind, interface, physical, policy):
    if policy.get("default") not in ("vpn", "direct") or not isinstance(policy.get("apps"), dict):
        raise ValueError("Invalid split policy")
    direct = {"type": "direct", "tag": "direct", "bind_interface": physical,
              "routing_mark": DIRECT_MARK}
    vpn = ({"type": "direct", "tag": "vpn", "bind_interface": interface, "routing_mark": VPN_MARK}
           if kind == "awg" else {"type": "socks", "tag": "vpn", "server": "127.0.0.1",
                                  "server_port": 10808, "version": "5"})
    # Leave DNS resolution to the existing system resolver and its servers.
    rules = [{"port": 53, "action": "route", "outbound": "direct"}]
    for application, outbound in policy["apps"].items():
        if not isinstance(application, str) or not application or outbound not in ("vpn", "direct"):
            raise ValueError("Invalid application rule")
        rule = app_rule(application, outbound)
        if kind == "awg" and outbound == "vpn":
            # The server AWG profile has IPv4 only. Never fall back to IPv6 WAN.
            reject = {key: value for key, value in rule.items() if key not in ("action", "outbound")}
            rules.append({**reject, "ip_version": 6, "action": "reject"})
        rules.append(rule)
    if kind == "awg" and policy["default"] == "vpn":
        rules.append({"ip_version": 6, "action": "reject"})
    return {
        "log": {"disabled": True},
        "inbounds": [{"type": "tun", "tag": "tun", "interface_name": "pino-tun",
                      "address": ["172.31.255.1/30", "fdfe:7069:6e6f::1/126"],
                      "auto_route": True, "strict_route": True, "stack": "mixed",
                      "iproute2_table_index": 2022, "iproute2_rule_index": 9000}],
        "outbounds": [direct, vpn],
        "route": {"rules": rules, "final": policy["default"],
                  "default_interface": physical},
    }


def awg_config(text):
    result = []
    interface = False
    for line in text.splitlines():
        clean = line.split("#", 1)[0].strip()
        if clean.startswith("["):
            if interface:
                result.extend(["Table = off", f"FwMark = {DIRECT_MARK}"])
            interface = clean == "[Interface]"
        if interface and "=" in clean:
            key = clean.split("=", 1)[0].strip()
            if key in ("Table", "FwMark", "SaveConfig"):
                continue
            if key in ("PreUp", "PostUp", "PreDown", "PostDown"):
                raise ValueError("Managed AWG clients must not contain shell hooks")
        result.append(line)
    if interface:
        result.extend(["Table = off", f"FwMark = {DIRECT_MARK}"])
    return "\n".join(result) + "\n"


def xray_config(config, physical, resolve=socket.getaddrinfo):
    result = copy.deepcopy(config)
    # Only accept the client shape produced by xray-client.py; ignore extra
    # listeners/routing from imported records when running a system tunnel.
    outbound = result["outbounds"][0]
    if outbound["protocol"] != "vless" or outbound["streamSettings"]["network"] != "xhttp":
        raise ValueError("Expected a VLESS/XHTTP client")
    stream = outbound["streamSettings"]
    if stream.get("security") != "tls" or stream["tlsSettings"].get("allowInsecure", False):
        raise ValueError("Xray client requires verified TLS")
    server = outbound["settings"]["vnext"][0]
    # Bootstrap DNS before TUN is up; TLS SNI and XHTTP host stay unchanged.
    address = resolve(server["address"], server["port"], socket.AF_INET, socket.SOCK_STREAM)[0][4][0]
    server["address"] = address
    stream["sockopt"] = {"mark": DIRECT_MARK, "interface": physical}
    return {"log": {"access": "none", "error": "none", "loglevel": "none"},
            "inbounds": [{"listen": "127.0.0.1", "port": 10808, "protocol": "socks",
                          "settings": {"auth": "noauth", "udp": True}}], "outbounds": [outbound]}


def check_router_resources():
    if run("ip", "link", "show", "pino-tun", check=False).returncode == 0:
        raise ValueError("pino-tun is already in use")
    for family in ("-4", "-6"):
        rules = json.loads(run("ip", family, "-j", "rule", "show").stdout)
        if any(rule.get("priority") in (100, 101) or 9000 <= rule.get("priority", -1) <= 9010 for rule in rules):
            raise ValueError("Reserved Pino routing priorities are already in use")
        for table in ("2022", "2025"):
            if run("ip", family, "route", "show", "table", table, check=False).stdout.strip():
                raise ValueError("Reserved Pino routing table is already in use")


def cleanup_router():
    # sing-box may exit before deleting its persistent TUN/routes after a SOCKS
    # session. Only these preflight-reserved resources belong to this service.
    for family in ("-4", "-6"):
        rules = json.loads(run("ip", family, "-j", "rule", "show").stdout)
        for rule in rules:
            priority = rule.get("priority", -1)
            if 9000 <= priority <= 9010:
                run("ip", family, "rule", "del", "priority", str(priority), check=False)
        run("ip", family, "route", "flush", "table", "2022", check=False)
    run("ip", "link", "delete", "pino-tun", check=False)


def cleanup_owned():
    ownership = RUNTIME / "owned.json"
    if not ownership.exists():
        return
    selected = json.loads(ownership.read_text())
    kind, name = selected["kind"], selected["name"]
    validate_connection(kind, name)
    cleanup_router()
    for family in ("-4", "-6"):
        run("ip", family, "rule", "del", "priority", "100", "fwmark", str(DIRECT_MARK), "lookup", "main", check=False)
    if kind == "awg":
        run("ip", "-4", "rule", "del", "priority", "101", "fwmark", str(VPN_MARK), "lookup", str(VPN_MARK), check=False)
        run("ip", "-4", "route", "del", "default", "dev", name, "table", str(VPN_MARK), check=False)
        path = RUNTIME / f"{name}.conf"
        if path.exists() and run("ip", "link", "show", name, check=False).returncode == 0:
            run("awg-quick", "down", str(path), check=False)
    ownership.unlink()


def serve():
    selected = json.loads((STATE / "selected.json").read_text())
    kind, name = selected["kind"], selected["name"]
    validate_connection(kind, name)
    routes = json.loads(run("ip", "-j", "-4", "route", "show", "default").stdout)
    if not routes:
        raise ValueError("No physical IPv4 default route")
    physical = routes[0]["dev"]
    check_router_resources()
    if kind == "awg" and run("ip", "link", "show", name, check=False).returncode == 0:
        raise ValueError("AWG interface already exists")
    RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
    write_json(RUNTIME / "owned.json", selected)
    children = []
    awg_path = RUNTIME / f"{name}.conf"
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        # Marked transport sockets bypass TUN, including kernel AWG packets.
        for family in ("-4", "-6"):
            run("ip", family, "rule", "add", "priority", "100", "fwmark", str(DIRECT_MARK), "lookup", "main")
        if kind == "awg":
            awg_path.write_text(awg_config(Path(f"/etc/amneziawg/{name}.conf").read_text()))
            awg_path.chmod(0o600)
            run("awg-quick", "up", str(awg_path))
            run("ip", "-4", "route", "add", "default", "dev", name, "table", str(VPN_MARK))
            run("ip", "-4", "rule", "add", "priority", "101", "fwmark", str(VPN_MARK), "lookup", str(VPN_MARK))
        else:
            config = xray_config(json.loads(Path(f"/etc/pino/xray-client/{name}.json").read_text()), physical)
            write_json(RUNTIME / "xray.json", config)
            run("xray", "run", "-test", "-config", str(RUNTIME / "xray.json"))
            children.append(subprocess.Popen(["xray", "run", "-config", str(RUNTIME / "xray.json")],
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            for _ in range(100):
                if children[0].poll() is not None:
                    raise ValueError("Xray client exited during startup")
                try:
                    with socket.create_connection(("127.0.0.1", 10808), timeout=.1):
                        break
                except OSError:
                    time.sleep(.05)
            else:
                raise ValueError("Xray SOCKS listener did not start")
        write_json(RUNTIME / "router.json", router_config(kind, name, physical, read_policy()))
        run("sing-box", "check", "-c", str(RUNTIME / "router.json"))
        children.append(subprocess.Popen(["sing-box", "run", "-c", str(RUNTIME / "router.json")],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        for _ in range(100):
            if any(child.poll() is not None for child in children):
                raise ValueError("Tunnel process exited during startup")
            if Path("/sys/class/net/pino-tun").exists():
                run("systemd-notify", "--ready")
                break
            time.sleep(.1)
        else:
            raise ValueError("TUN interface did not start")
        while not stopping:
            if any(child.poll() is not None for child in children):
                raise ValueError("Tunnel process exited")
            time.sleep(.2)
    finally:
        for child in reversed(children):
            child.terminate()
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        cleanup_owned()


def validate_connection(kind, name):
    if kind not in ("awg", "xray") or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,14}", name):
        raise ValueError("Invalid tunnel connection")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["serve", "cleanup", "connect", "disconnect", "status", "split", "list", "active-awg"])
    parser.add_argument("args", nargs="*")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if os.geteuid() != 0:
            raise ValueError("Run through pino with sudo")
        if args.operation == "serve":
            serve()
        elif args.operation == "cleanup":
            cleanup_owned()
        elif args.operation == "connect":
            if len(args.args) != 2:
                raise ValueError("connect requires kind and name")
            kind, name = args.args
            validate_connection(kind, name)
            path = Path(f"/etc/amneziawg/{name}.conf" if kind == "awg" else f"/etc/pino/xray-client/{name}.json")
            if not path.is_file():
                raise ValueError("Connection is not provisioned locally")
            write_json(STATE / "selected.json", {"kind": kind, "name": name})
            run("systemctl", "restart", SERVICE)
            print(f"Connected {kind}/{name}; autostart enabled")
        elif args.operation == "disconnect":
            if args.args:
                if len(args.args) != 2:
                    raise ValueError("disconnect expects an optional kind/name pair")
                path = STATE / "selected.json"
                if not path.exists() or json.loads(path.read_text()) != dict(zip(("kind", "name"), args.args)):
                    return 0
            run("systemctl", "stop", SERVICE)
            (STATE / "selected.json").unlink(missing_ok=True)
        elif args.operation == "status":
            path = STATE / "selected.json"
            print(path.read_text().strip() if path.exists() else "No selected tunnel")
            print(run("systemctl", "is-active", SERVICE, check=False).stdout.strip())
        elif args.operation == "active-awg":
            selected = json.loads((STATE / "selected.json").read_text())
            if selected["kind"] != "awg" or run("systemctl", "is-active", "--quiet", SERVICE, check=False).returncode:
                raise ValueError("No active AWG tunnel")
            print(selected["name"])
        elif args.operation == "list":
            kind = args.args[0] if args.args else "awg"
            if kind not in ("awg", "xray"):
                raise ValueError("Invalid tunnel kind")
            directory, suffix = ((Path("/etc/amneziawg"), ".conf") if kind == "awg"
                                 else (Path("/etc/pino/xray-client"), ".json"))
            selected_path = STATE / "selected.json"
            selected = json.loads(selected_path.read_text()) if selected_path.exists() else {}
            active = run("systemctl", "is-active", "--quiet", SERVICE, check=False).returncode == 0
            print(f"{'CONNECTION':18} {'ACTIVE':10} AUTOSTART")
            for path in sorted(directory.glob("*" + suffix)):
                match = selected == {"kind": kind, "name": path.stem}
                print(f"{path.stem:18} {('yes' if match and active else 'no'):10} {'yes' if match else 'no'}")
        elif args.operation == "split":
            policy = read_policy()
            action = args.args[0] if args.args else "list"
            if action == "list" and len(args.args) <= 1:
                print(json.dumps(policy, indent=2))
                return 0
            if action == "default" and len(args.args) == 2 and args.args[1] in ("vpn", "direct"):
                policy["default"] = args.args[1]
            elif action == "add" and len(args.args) == 3 and args.args[1] in ("vpn", "direct"):
                application = args.args[2]
                if not application or any(ord(c) < 32 for c in application):
                    raise ValueError("Invalid application")
                policy["apps"][application] = args.args[1]
            elif action == "remove" and len(args.args) == 2:
                policy["apps"].pop(args.args[1], None)
            else:
                raise ValueError("split: list | default vpn/direct | add vpn/direct executable | remove executable")
            write_json(STATE / "split.json", policy)
            if run("systemctl", "is-active", "--quiet", SERVICE, check=False).returncode == 0:
                run("systemctl", "restart", SERVICE)
            print("Application routing updated; reconnect existing application sessions")
        return 0
    except ValueError:
        print("Invalid or conflicting tunnel configuration; check the selected connection and split rules.", file=sys.stderr)
        return 1
    except (KeyError, IndexError, TypeError, OSError, subprocess.CalledProcessError):
        # Subprocess diagnostics/config parsing can contain private credentials.
        print("Tunnel operation failed; check provisioned configs, network and systemd lifecycle status. Secret output suppressed.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
