#!/usr/bin/env python3
"""Render public policy plus private user credentials without printing either."""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import uuid


def users(kind, secret):
    entries = secret.get("users") if isinstance(secret, dict) else None
    if not isinstance(entries, dict) or not entries:
        raise ValueError("Expected a non-empty users object")
    result = {}
    for name, key in entries.items():
        if not isinstance(name, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", name):
            raise ValueError("Invalid user name")
        if not isinstance(key, str):
            raise ValueError("Invalid user credential")
        if kind == "xray":
            try:
                normalized = str(uuid.UUID(key))
            except ValueError:
                raise ValueError("Invalid Xray UUID") from None
            if key != normalized or uuid.UUID(key).int == 0:
                raise ValueError("Expected a canonical nonzero UUID")
        elif not re.fullmatch(r"[0-9a-f]{32}", key) or key == "0" * 32:
            raise ValueError("Expected a nonzero 32-character lowercase hex secret")
        if key in result.values():
            raise ValueError("Users must have distinct credentials")
        result[name] = key
    return result


def render(kind, settings, secret):
    entries = users(kind, secret)
    if kind == "xray":
        return json.dumps({
            "log": {"access": "none", "error": "none", "loglevel": "none"},
            "inbounds": [{
                "listen": "127.0.0.1", "port": settings["port"], "protocol": "vless",
                "settings": {"decryption": "none", "clients": [
                    {"id": key, "email": name} for name, key in entries.items()]},
                "streamSettings": {"network": "xhttp", "security": "none",
                                   "xhttpSettings": {"path": settings["path"], "mode": "auto"}},
            }],
            "outbounds": [{"tag": "internet", "protocol": "freedom"},
                          {"tag": "blocked", "protocol": "blackhole"}],
            "routing": {"domainStrategy": "IPIfNonMatch", "rules": [
                {"type": "field", "ip": [
                    "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
                    "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16",
                    "224.0.0.0/4", "240.0.0.0/4", "::/128", "::1/128",
                    "fc00::/7", "fe80::/10", "ff00::/8",
                ], "outboundTag": "blocked"},
            ]},
        }) + "\n"
    domain = settings["tlsDomain"]
    if not re.fullmatch(r"[a-zA-Z0-9.-]+", domain):
        raise ValueError("Invalid TLS masking domain")
    return f'''[general]
use_middle_proxy = true
log_level = "silent"
[general.modes]
classic = false
secure = false
tls = true
[general.links]
show = []
[server]
port = {settings["port"]}
[server.api]
enabled = false
[[server.listeners]]
ip = "0.0.0.0"
[censorship]
tls_domain = "{domain}"
mask = true
tls_emulation = true
tls_front_dir = "tlsfront"
[access.users]
''' + "".join(f'{json.dumps(name)} = {json.dumps(key)}\n' for name, key in entries.items())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=["xray", "telemt"])
    parser.add_argument("settings", type=Path)
    parser.add_argument("credentials", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        content = render(args.kind, json.loads(args.settings.read_text()),
                         json.loads(args.credentials.read_text()))
        os.umask(0o077)
        args.output.write_text(content)
        args.output.chmod(0o600)
    except (OSError, ValueError, KeyError, TypeError):
        print("Invalid proxy credentials or runtime configuration; no secret values logged", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
