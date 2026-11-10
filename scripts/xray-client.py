#!/usr/bin/env python3
"""Manage Xray users and client exports without displaying credentials."""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid
from urllib.parse import urlencode

source = Path(os.environ.get("PINO_SERVER_SECRETS", Path(__file__).with_name("server-secrets.py")))
spec = importlib.util.spec_from_file_location("server_secrets", source)
secrets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(secrets)


def validate(host, name):
    if host not in ("mosk", "halos") or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,31}", name):
        raise ValueError("Expected mosk/halos and a client name of 1–32 letters, digits, underscores or hyphens")


def settings(host):
    variable = "PINO_PROXY_SETTINGS" if host == "mosk" else "PINO_HALOS_PROXY_SETTINGS"
    path = Path(os.environ.get(variable, Path(__file__).resolve().parents[1] / f"resources/{host}-proxies.json"))
    return json.loads(path.read_text())["xray"]


def client_config(host, identifier):
    public = settings(host)
    return {
        "log": {"access": "none", "error": "none", "loglevel": "none"},
        "inbounds": [{"listen": "127.0.0.1", "port": 10808, "protocol": "socks",
                      "settings": {"auth": "noauth", "udp": True}}],
        "outbounds": [{"protocol": "vless", "settings": {"vnext": [{
            "address": public["domain"], "port": 443,
            "users": [{"id": identifier, "encryption": "none"}],
        }]}, "streamSettings": {"network": "xhttp", "security": "tls",
            "tlsSettings": {"serverName": public["domain"], "alpn": ["h2"]},
            "xhttpSettings": {"host": public["domain"], "path": public["path"], "mode": "auto"}}}],
    }


def connection_uri(host, name, identifier):
    public = settings(host)
    return f"vless://{identifier}@{public['domain']}:443?" + urlencode({
        "encryption": "none", "security": "tls", "sni": public["domain"],
        "type": "xhttp", "path": public["path"], "mode": "auto", "alpn": "h2",
    }) + f"#{host}-{name}"


def client_id(record):
    try:
        config = json.loads(record["notes"])
        identifier = config["outbounds"][0]["settings"]["vnext"][0]["users"][0]["id"]
        if str(uuid.UUID(identifier)) != identifier or uuid.UUID(identifier).int == 0:
            raise ValueError()
        return identifier
    except (ValueError, KeyError, TypeError, IndexError, AttributeError):
        raise ValueError("Invalid saved Xray client; existing records preserved") from None


def prepare_client(vault, host, name):
    validate(host, name)
    server_name = f"pino-xray-{host}"
    server = vault.find(server_name, 2)
    if not server:
        raise ValueError("Prepare the server Xray note first")
    secrets.validate_proxy_note(server_name, server["notes"])
    payload = json.loads(server["notes"])
    item_name = f"pino-xray-client-{name}-{host}"
    existing = vault.find(item_name, 2)
    identifier = client_id(existing) if existing else payload["users"].get(name, str(uuid.uuid4()))
    if name in payload["users"] and payload["users"][name] != identifier:
        raise ValueError("Server and saved client credentials disagree; records preserved")
    if any(user != name and key == identifier for user, key in payload["users"].items()):
        raise ValueError("Credential already belongs to another user")
    config = json.dumps(client_config(host, identifier), indent=2) + "\n"
    uri = connection_uri(host, name, identifier)
    link = vault.find(item_name + "-link", 2)
    if not existing:
        vault.create(item_name, 2, notes=config)
    elif existing["notes"] != config:
        updated = copy.deepcopy(existing)
        updated["notes"] = config
        vault.edit(existing, updated)
    if payload["users"].get(name) != identifier:
        payload["users"][name] = identifier
        updated = copy.deepcopy(server)
        updated["notes"] = json.dumps(payload, indent=2)
        vault.edit(server, updated)
    if not link:
        vault.create(item_name + "-link", 2, notes=uri)
    elif link["notes"] != uri:
        updated = copy.deepcopy(link)
        updated["notes"] = uri
        vault.edit(link, updated)
    return config, uri


def deploy_server(vault, host):
    result = subprocess.run(["pino", "os", "provision", "send", f"pino-xray-{host}", host,
                             "/etc/pino/xray/users.json", "xray.service"], env=vault.env)
    if result.returncode:
        raise ValueError("Deployment failed; saved records retained. Retry the same add-client/remove-client command without an export directory.")


def remove_client(vault, host, name):
    validate(host, name)
    server_name = f"pino-xray-{host}"
    server = vault.find(server_name, 2)
    if not server:
        raise ValueError("Server note missing; client records preserved")
    secrets.validate_proxy_note(server_name, server["notes"])
    payload = json.loads(server["notes"])
    item_name = f"pino-xray-client-{name}-{host}"
    client = vault.find(item_name, 2)
    link = vault.find(item_name + "-link", 2)
    if name in payload["users"]:
        if client and client_id(client) != payload["users"][name]:
            raise ValueError("Server and saved client credentials disagree; records preserved")
        if len(payload["users"]) == 1:
            raise ValueError("Cannot remove the last Xray user; add another user first")
        del payload["users"][name]
        updated = copy.deepcopy(server)
        updated["notes"] = json.dumps(payload, indent=2)
        updated["fields"] = [field for field in server.get("fields", [])
                             if field.get("name") != f"{name} connection URI"]
        vault.edit(server, updated)
    # Always redeploy: a previous attempt may have saved the vault update but
    # failed before the live server revoked the user.
    deploy_server(vault, host)
    if link:
        vault.delete(link)
    if client:
        vault.delete(client)
    print("Xray user revoked; client records moved to Bitwarden trash. Local exports are unchanged.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["add-client", "remove-client"])
    parser.add_argument("host", choices=["mosk", "halos"])
    parser.add_argument("name")
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--yes", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        validate(args.host, args.name)
        if args.operation == "remove-client":
            if args.output:
                raise ValueError("Removal does not accept an export directory")
            if not args.yes:
                if not sys.stdin.isatty():
                    raise ValueError("Use an interactive terminal or --yes to confirm removal")
                if input(f"Revoke {args.name} on {args.host}? Type yes: ") != "yes":
                    return 0
            remove_client(secrets.Bitwarden(), args.host, args.name)
            return 0
        if args.yes:
            raise ValueError("--yes is only for removal")
        output = args.output.expanduser().resolve() if args.output else None
        if output:
            if output.exists():
                raise ValueError("Export directory exists; retry without the directory to deploy saved records")
            ancestor = output.parent
            while not ancestor.exists():
                ancestor = ancestor.parent
            if subprocess.run(["git", "-C", str(ancestor), "rev-parse", "--is-inside-work-tree"],
                              capture_output=True).returncode == 0:
                raise ValueError("Export outside Git repositories")
        vault = secrets.Bitwarden()
        config, uri = prepare_client(vault, args.host, args.name)
        if output:
            output.mkdir(mode=0o700, parents=True)
            secrets.write_private(output / f"{args.host}-{args.name}.json", config)
            secrets.write_private(output / f"{args.host}-{args.name}.uri", uri + "\n")
        print("Xray client config and connection URI saved in Bitwarden.")
        deploy_server(vault, args.host)
        print("Xray user deployed.")
        return 0
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print(str(error) if isinstance(error, ValueError) else "Xray client operation failed; secret contents suppressed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
