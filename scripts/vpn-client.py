#!/usr/bin/env python3
"""Manage AWG clients, AmneziaVPN links and server peers in Bitwarden."""
import argparse
import base64
import copy
import hashlib
import importlib.util
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zlib

source = Path(os.environ.get("PINO_SERVER_SECRETS", Path(__file__).with_name("server-secrets.py")))
spec = importlib.util.spec_from_file_location("server_secrets", source)
secrets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(secrets)


def sections(text):
    result = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line in ("[Interface]", "[Peer]"):
            result.append((line[1:-1], {}))
        elif result and "=" in line:
            key, value = (part.strip() for part in line.split("=", 1))
            if key in result[-1][1]:
                raise ValueError("Duplicate VPN configuration field")
            result[-1][1][key] = value
        else:
            raise ValueError("Invalid VPN configuration")
    if not result or result[0][0] != "Interface" or any(s != "Peer" for s, _ in result[1:]):
        raise ValueError("Expected one Interface followed by Peers")
    return result[0][1], [fields for _, fields in result[1:]]


def public_key(private):
    return subprocess.run(["awg", "pubkey"], input=private + "\n",
                          capture_output=True, text=True, check=True).stdout.strip()


def reconcile_clients(vault, host, names):
    """Restore explicitly named clients without touching the running server."""
    names = list(dict.fromkeys(names))
    if not names:
        raise ValueError("Specify the clients to reconcile")
    for name in names:
        validate_client(host, name)
    server = vault.find(f"pino-vpn-server-{host}", 2)
    if not server:
        raise ValueError("VPN server note is missing")
    text = server["notes"]
    lines = text.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.split("#", 1)[0].strip() == "[Peer]"]
    blocks = []
    for start, end in zip(starts, starts[1:] + [len(lines)]):
        block = lines[start:end]
        _, peers = sections("[Interface]\n" + "".join(block))
        label = next((line.strip()[1:].strip() for line in block
                      if line.strip().startswith("#") and line.strip()[1:].strip()), "")
        blocks.append((start, end, label, peers[0]))
    owners = {}
    prefix, suffix = "pino-vpn-client-", f"-{host}"
    for item in vault.json_call("list", "items", "--search", prefix):
        item_name = item.get("name", "")
        if item.get("deletedDate") or not item_name.startswith(prefix) or not item_name.endswith(suffix):
            continue
        owner = item_name[len(prefix):-len(suffix)]
        validate_client(host, owner)
        client = vault.find(item_name, 2)
        client_interface, _ = sections(client["notes"])
        key = public_key(client_interface["PrivateKey"])
        if key in owners:
            raise ValueError("Duplicate VPN client key; no records changed")
        owners[key] = owner
    to_remove = []
    for name in names:
        matches = [(start, end, peer) for start, end, label, peer in blocks if label == name]
        client = vault.find(f"pino-vpn-client-{name}-{host}", 2)
        if matches:
            for start, end, peer in matches:
                owner = owners.get(peer.get("PublicKey"))
                if owner and owner != name:
                    raise ValueError(f"A server peer named {name} belongs to client {owner}; no records changed")
                to_remove.append((start, end))
            if client:
                client_interface, _ = sections(client["notes"])
                client_key = public_key(client_interface["PrivateKey"])
                if any(other.get("PublicKey") == client_key and label != name for _, _, label, other in blocks):
                    raise ValueError(f"Client {name} belongs to another server peer; no records changed")
        elif not client:
            raise ValueError(f"Client {name} has no saved profile or named server peer; no records changed")
    changed = copy.deepcopy(server)
    for start, end in sorted(to_remove, reverse=True):
        del lines[start:end]
    changed["notes"] = "".join(lines)
    try:
        if changed != server:
            vault.edit(server, changed)
        for name in names:
            prepare_client(vault, host, name, force=True)
    except (ValueError, OSError, subprocess.CalledProcessError):
        print("VPN reconciliation interrupted; inspect Bitwarden before retrying. The server was not changed.", file=sys.stderr)
        raise
    print("VPN clients reconciled in Bitwarden: " + ", ".join(names))


def rotate_credentials(vault, host):
    """Replace server and all managed peer keys after validating every peer."""
    server = vault.find(f"pino-vpn-server-{host}", 2)
    if not server:
        raise ValueError("VPN server note is missing")
    interface, peers = sections(server["notes"])
    public_key(interface["PrivateKey"])
    prefix, suffix = "pino-vpn-client-", f"-{host}"
    records = vault.json_call("list", "items", "--search", prefix)
    clients = {}
    for item in records:
        name = item.get("name", "")
        if item.get("deletedDate") or not name.startswith(prefix) or not name.endswith(suffix):
            continue
        user = name[len(prefix):-len(suffix)]
        validate_client(host, user)
        if user in clients or item.get("type") != 2:
            raise ValueError("Duplicate or invalid VPN client record; no records changed")
        item = vault.find(name, 2)
        client_interface, destinations = sections(item["notes"])
        if len(destinations) != 1 or not destinations[0].get("PublicKey"):
            raise ValueError(f"VPN client {user} must have exactly one server peer with a public key; no records changed")
        key = public_key(client_interface["PrivateKey"])
        if key in clients:
            raise ValueError("Duplicate VPN client key; no records changed")
        clients[key] = (user, item, client_interface, destinations[0])
    peer_keys = [peer.get("PublicKey") for peer in peers]
    if len(peer_keys) != len(set(peer_keys)):
        raise ValueError("VPN server has duplicate peer keys; no records changed")
    missing_clients = set(peer_keys) - set(clients)
    inactive_clients = set(clients) - set(peer_keys)
    if missing_clients or inactive_clients:
        issues = []
        if inactive_clients:
            names = sorted(clients[key][0] for key in inactive_clients)
            issues.append("saved clients without a matching server peer: " + ", ".join(names))
        if missing_clients:
            blocks = re.split(r"(?m)^[ \t]*\[Peer\][ \t]*(?:#.*)?$", server["notes"])[1:]
            labels = []
            for index, (block, peer) in enumerate(zip(blocks, peers), 1):
                if peer.get("PublicKey") not in missing_clients:
                    continue
                label = next((line.strip()[1:].strip() for line in block.splitlines()
                              if line.strip().startswith("#") and line.strip()[1:].strip()), "")
                labels.append(label if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,31}", label) else f"peer-{index}")
            issues.append("server peers without a matching saved client: " + ", ".join(labels or ["unknown"]))
        raise ValueError("VPN records differ: " + "; ".join(issues) + ". No records changed")
    new_server_private = subprocess.run(["awg", "genkey"], capture_output=True, text=True, check=True).stdout.strip()
    if not new_server_private:
        raise ValueError("Could not generate VPN server key")
    new_server_public = public_key(new_server_private)
    server_text = secrets.replace_vpn_key(server["notes"], new_server_private)
    updates = []
    generated = set(peer_keys)
    for old_public, (user, item, client_interface, peer) in clients.items():
        private = subprocess.run(["awg", "genkey"], capture_output=True, text=True, check=True).stdout.strip()
        if not private:
            raise ValueError("Could not generate VPN client key")
        new_public = public_key(private)
        if new_public in generated:
            raise ValueError("Generated duplicate VPN client key")
        generated.add(new_public)
        server_text, count = re.subn(r"(?m)^([ \t]*PublicKey[ \t]*=[ \t]*)" + re.escape(old_public) + r"[ \t]*$", lambda m: m.group(1) + new_public, server_text)
        if count != 1:
            raise ValueError("Cannot update VPN server peer safely")
        client_text = secrets.replace_vpn_key(item["notes"], private)
        client_text, count = re.subn(r"(?m)^([ \t]*PublicKey[ \t]*=[ \t]*)" + re.escape(peer["PublicKey"]) + r"[ \t]*$", lambda m: m.group(1) + new_server_public, client_text)
        if count != 1:
            raise ValueError("Cannot update VPN client server key safely")
        endpoint = "mosk.egrapa.com" if host == "mosk" else "halos.egrapa.com"
        client_text, count = re.subn(r"(?m)^([ \t]*Endpoint[ \t]*=[ \t]*)[^\s:]+:(\d+)[ \t]*$", lambda m: m.group(1) + endpoint + ":" + m.group(2), client_text)
        if count != 1:
            raise ValueError("Cannot update VPN client endpoint safely")
        updated = copy.deepcopy(item)
        updated["notes"] = client_text
        updates.append((item, updated))
        link = vault.find(f"{prefix}{user}{suffix}-amnezia", 2)
        if link:
            changed = copy.deepcopy(link)
            changed["notes"] = amnezia_link(client_text, f"{host}-{user}")
            updates.append((link, changed))
    changed_server = copy.deepcopy(server)
    changed_server["notes"] = server_text
    try:
        for original, changed in updates:
            vault.edit(original, changed)
        vault.edit(server, changed_server)
    except (ValueError, OSError, subprocess.CalledProcessError):
        print("VPN rotation interrupted; check server and client records in Bitwarden before retrying.", file=sys.stderr)
        raise
    print(f"Updated VPN server and {len(clients)} client credentials in Bitwarden. Reinstall client profiles after provisioning.")


def peer_networks(peers, excluding=None):
    try:
        return [ipaddress.ip_network(value.strip()) for peer in peers
                if peer.get("PublicKey") != excluding
                for value in peer["AllowedIPs"].split(",")]
    except (ValueError, KeyError):
        raise ValueError("Invalid server peer AllowedIPs") from None


def update_peer_address(config, public, address):
    # Use the same comment/whitespace rules as sections(), retaining every
    # unrelated line, including hooks, comments and optional peer settings.
    lines = config.splitlines(keepends=True)
    starts = [index for index, line in enumerate(lines)
              if line.split("#", 1)[0].strip() == "[Peer]"]
    for start, end in zip(starts, starts[1:] + [len(lines)]):
        _, peers = sections("[Interface]\n" + "".join(lines[start:end]))
        if peers[0].get("PublicKey") == public:
            for index in range(start, end):
                if re.match(r"^[ \t]*AllowedIPs[ \t]*=", lines[index]):
                    lines[index] = f"AllowedIPs = {address}\n"
                    return "".join(lines)
    raise ValueError("Could not locate the existing peer address")


def amnezia_link(config, description):
    # Match AmneziaVPN's extractWireGuardConfig and Qt qCompress framing.
    interface, peers = sections(config)
    if len(peers) != 1:
        raise ValueError("AmneziaVPN export requires exactly one server peer")
    peer = peers[0]
    endpoint, port = peer["Endpoint"].rsplit(":", 1)
    if not endpoint or not port.isascii() or not port.isdigit() or not 1 <= int(port) <= 65535:
        raise ValueError("Invalid client Endpoint")
    last = {
        "config": config, "hostName": endpoint.strip("[]"), "port": int(port),
        "client_priv_key": interface["PrivateKey"], "client_ip": interface["Address"],
        "server_pub_key": peer["PublicKey"],
        "allowed_ips": [value.strip() for value in peer["AllowedIPs"].split(",")],
        "mtu": interface.get("MTU", "1280"),
    }
    for key, value in interface.items():
        if re.fullmatch(r"Jc|Jmin|Jmax|S[1-4]|H[1-4]|I[1-5]", key):
            last[key] = value
    for source, target in (("PresharedKey", "psk_key"), ("PersistentKeepalive", "persistent_keep_alive")):
        if source in peer:
            last[target] = peer[source]
    payload = {
        "containers": [{"container": "amnezia-awg", "awg": {
            "last_config": json.dumps(last), "isThirdPartyConfig": True,
            "port": port, "transport_proto": "udp",
        }}],
        "defaultContainer": "amnezia-awg", "description": description,
        "hostName": last["hostName"],
    }
    dns = [value.strip() for value in interface.get("DNS", "").split(",") if value.strip()]
    for index, value in enumerate(dns[:2], 1):
        payload[f"dns{index}"] = value
    encoded = json.dumps(payload, separators=(",", ":")).encode()
    compressed = len(encoded).to_bytes(4, "big") + zlib.compress(encoded, 8)
    return "vpn://" + base64.urlsafe_b64encode(compressed).decode().rstrip("=")


def validate_client(host, name):
    if host not in ("mosk", "halos") or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,31}", name):
        raise ValueError("Use host mosk or halos and a client name of 1–32 letters, digits, hyphens or underscores")


def list_users(vault, kind, host):
    if kind not in ("awg", "xray") or host not in ("mosk", "halos"):
        raise ValueError("Use awg or xray and host mosk or halos")
    item = f"pino-vpn-server-{host}" if kind == "awg" else f"pino-xray-{host}"
    note = vault.find(item, 2)
    if not note:
        raise ValueError("Server Bitwarden note is missing")
    if kind == "awg":
        text = note.get("notes") or ""
        _, peers = sections(text)
        blocks = re.split(r"(?m)^\s*\[Peer\]\s*$", text)[1:]
        entries = []
        for index, (block, peer) in enumerate(zip(blocks, peers), 1):
            label = next((line.strip()[1:].strip() for line in block.splitlines()
                          if line.strip().startswith("#") and line.strip()[1:].strip()), f"unnamed-{index}")
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,31}", label):
                label = f"unnamed-{index}"
            entries.append((label, peer.get("PublicKey", "")))
        remote_args = ["server", "vpn", "peers"]
    else:
        payload = json.loads(note.get("notes") or "")
        secrets.validate_proxy_note(item, note.get("notes"))
        entries = [(name, hashlib.sha256(value.encode()).hexdigest()) for name, value in payload["users"].items()]
        remote_args = ["server", "xray", "users"]
    result = subprocess.run(["pino", "host", host, *remote_args], capture_output=True, text=True)
    if result.returncode:
        print("SSH verification unavailable; showing Bitwarden entries only.", file=sys.stderr)
        for name, _ in entries:
            print(f"{name}\tunverified")
        return
    if kind == "xray":
        rows = [line.split("\t", 1) for line in result.stdout.splitlines()]
        if any(len(row) != 2 or not re.fullmatch(r"[0-9a-f]{64}", row[1]) for row in rows):
            print("SSH verification returned an invalid response; showing Bitwarden entries only.", file=sys.stderr)
            for name, _ in entries:
                print(f"{name}\tunverified")
            return
        remote_users = dict(rows)
        for name, digest in entries:
            status = "vault only" if name not in remote_users else ("present" if remote_users[name] == digest else "different credential")
            print(f"{name}\t{status}")
        for index, name in enumerate(sorted(set(remote_users) - {name for name, _ in entries}), 1):
            label = name if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,31}", name) else f"unknown-peer-{index}"
            print(f"{label}\tserver only")
        return
    remote = set(re.findall(r"(?m)^peer:\s*(\S+)\s*$", result.stdout))
    for name, key in entries:
        print(f"{name}\t{'present' if key in remote else 'vault only'}")
    missing = remote - {key for _, key in entries}
    for index, name in enumerate(sorted(missing), 1):
        label = name if kind == "xray" and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,31}", name) else f"unknown-peer-{index}"
        print(f"{label}\tserver only")


def prepare_client(vault, host, name, force=False):
    validate_client(host, name)
    server = vault.find(f"pino-vpn-server-{host}", 2)
    if not server:
        raise ValueError("Prepare the server Bitwarden note first")
    interface, peers = sections(server["notes"])
    try:
        address = ipaddress.IPv4Interface(interface["Address"])
    except (ValueError, KeyError):
        raise ValueError("Invalid server Interface Address") from None
    if address.network.prefixlen < 16:
        raise ValueError("VPN subnet is unexpectedly large")
    server_public = public_key(interface["PrivateKey"])
    item_name = f"pino-vpn-client-{name}-{host}"
    existing = vault.find(item_name, 2)
    used = peer_networks(peers)
    client = None
    if existing:
        client, destinations = sections(existing["notes"])
        try:
            old_interface = ipaddress.IPv4Interface(client["Address"])
        except (ValueError, KeyError):
            raise ValueError("Invalid client Interface Address; record preserved") from None
    if existing and not force:
        client_address = old_interface
        if (len(destinations) != 1 or destinations[0].get("PublicKey") != server_public
                or destinations[0].get("AllowedIPs") != "0.0.0.0/0"
                or client_address.network.prefixlen != 32
                or client_address.ip not in address.network
                or client_address.ip in (address.ip, address.network.network_address, address.network.broadcast_address)):
            raise ValueError("Existing client does not match the full-IPv4 profile; use --force to update it")
        config = existing["notes"]
        public = public_key(client["PrivateKey"])
    else:
        old_address = None
        if existing:
            private = client["PrivateKey"]
            public = public_key(private)
            old_address = old_interface.ip
            # Preserve the device key, so a failed vault update can be retried
            # without losing track of an old peer or revoking another device.
            used = peer_networks(peers, excluding=public)
        else:
            private = subprocess.run(["awg", "genkey"], capture_output=True, text=True, check=True).stdout.strip()
            public = public_key(private)
        candidate = next((ip for ip in address.network.hosts()
                          if ip != address.ip and not any(ip in network for network in used)), None)
        if (old_address is not None and old_address in address.network
                and old_address not in (address.ip, address.network.network_address, address.network.broadcast_address)
                and not any(old_address in network for network in used)):
            candidate = old_address
        if candidate is None:
            raise ValueError("No available VPN client addresses")
        client_address = ipaddress.IPv4Interface(f"{candidate}/32")
        # Copy only AWG protocol parameters, never server hooks or its private key.
        parameters = {key: value for key, value in interface.items()
                      if re.fullmatch(r"Jc|Jmin|Jmax|S[1-4]|H[1-4]|I[1-5]", key)}
        config = f"[Interface]\nPrivateKey = {private}\nAddress = {client_address}\n"
        config += "".join(f"{key} = {value}\n" for key, value in parameters.items())
        port = interface.get("ListenPort", "585")
        if not port.isascii() or not port.isdigit() or not 1 <= int(port) <= 65535:
            raise ValueError("Invalid server ListenPort")
        endpoint = "mosk.egrapa.com" if host == "mosk" else "halos.egrapa.com"
        config += (f"\n[Peer]\nPublicKey = {server_public}\n"
                   f"Endpoint = {endpoint}:{port}\n"
                   "AllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 25\n")
        matching = [peer for peer in peers if peer.get("PublicKey") == public]
        if len(matching) > 1:
            raise ValueError("Duplicate server peers for this device; resolve them first")
        if matching and matching[0].get("PresharedKey"):
            config += f"PresharedKey = {matching[0]['PresharedKey']}\n"
    if any(client_address.ip in network for network in peer_networks(peers, excluding=public)):
        raise ValueError("Client address is already assigned to another peer")
    updated = copy.deepcopy(server)
    matching = [p for p in peers if p.get("PublicKey") == public]
    if matching:
        if len(matching) != 1:
            raise ValueError("Existing server peer has a conflicting address")
        if matching[0].get("AllowedIPs") != str(client_address):
            if not force:
                raise ValueError("Existing server peer has a conflicting address; retry with --force")
            updated["notes"] = update_peer_address(server["notes"], public, client_address)
    else:
        updated["notes"] = server["notes"].rstrip() + (
            f"\n\n[Peer]\n# {name}\nPublicKey = {public}\nAllowedIPs = {client_address}\n")

    link_name = f"{item_name}-amnezia"
    existing_link = vault.find(link_name, 2)
    link = amnezia_link(config, f"{host}-{name}")

    # Finish all validation before the first vault mutation. Save the client
    # first so that a failed server edit can be recovered by rerunning.
    if not existing:
        vault.create(item_name, 2, notes=config)
    elif force and config != existing["notes"]:
        updated_client = copy.deepcopy(existing)
        updated_client["notes"] = config
        vault.edit(existing, updated_client)
    if updated != server:
        vault.edit(server, updated)
    if not existing_link:
        vault.create(link_name, 2, notes=link)
    elif existing_link.get("notes") != link:
        updated_link = copy.deepcopy(existing_link)
        updated_link["notes"] = link
        vault.edit(existing_link, updated_link)
    return config


def deploy_server(vault, host):
    result = subprocess.run([
        os.environ["PINO_PROVISION_SEND"], "send", f"pino-vpn-server-{host}", host,
        "/etc/pino/vpn/awg0.conf", "amneziawg-server.service", "pino-vpn-mode.service",
    ], env=vault.env)
    if result.returncode:
        raise ValueError("Server deployment failed; vault state retained. Retry the same client command.")


def remove_client(vault, host, name):
    validate_client(host, name)
    item_name = f"pino-vpn-client-{name}-{host}"
    client = vault.find(item_name, 2)
    link = vault.find(f"{item_name}-amnezia", 2)
    if not client:
        if link:
            raise ValueError("Client config missing; cannot identify its peer safely. Restore it before removal.")
        print("Client records are already absent; no server peer was changed.")
        return
    server = vault.find(f"pino-vpn-server-{host}", 2)
    if not server:
        raise ValueError("Server note missing; client records preserved")
    interface, _ = sections(client["notes"])
    public = public_key(interface["PrivateKey"])
    _, peers = sections(server["notes"])
    if sum(peer.get("PublicKey") == public for peer in peers) > 1:
        raise ValueError("Duplicate server peers; resolve them before removal")
    lines = server["notes"].splitlines(keepends=True)
    starts = [index for index, line in enumerate(lines)
              if line.split("#", 1)[0].strip() == "[Peer]"]
    updated = copy.deepcopy(server)
    for start, end in zip(starts, starts[1:] + [len(lines)]):
        _, block = sections("[Interface]\n" + "".join(lines[start:end]))
        if block[0].get("PublicKey") == public:
            updated["notes"] = "".join(lines[:start] + lines[end:])
            break
    if updated != server:
        vault.edit(server, updated)
    # Keep the canonical client until deployment and companion deletion succeed,
    # so every partial failure can be retried with the same device identity.
    deploy_server(vault, host)
    if link:
        vault.delete(link)
    vault.delete(client)
    print("Server peer revoked; client config and AmneziaVPN link moved to Bitwarden trash.")
    print("Previously exported local files are not removed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", choices=["mosk", "halos"])
    parser.add_argument("name", nargs="?")
    parser.add_argument("output", type=Path, nargs="?", help="New export directory outside Git")
    parser.add_argument("--remove", action="store_true", help="Revoke the peer and trash both Bitwarden client records")
    parser.add_argument("--yes", action="store_true", help="Confirm removal without prompting")
    parser.add_argument("--force", action="store_true", help="Replace an existing Bitwarden client profile, preserving its device key; export directory must still be new")
    parser.add_argument("--list", choices=["awg", "xray"], dest="list_kind")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.list_kind:
            if args.name or args.output or args.remove or args.force or args.yes:
                raise ValueError("Listing accepts only kind and host")
            list_users(secrets.Bitwarden(), args.list_kind, args.host)
            return 0
        if args.name is None:
            raise ValueError("Client name is required")
        validate_client(args.host, args.name)
        if args.remove:
            if args.output or args.force:
                raise ValueError("Removal does not accept an export directory or --force")
            if not args.yes:
                if not sys.stdin.isatty():
                    raise ValueError("Removal requires an interactive confirmation or --yes")
                if input(f"Revoke {args.name} on {args.host} and trash its Bitwarden records? Type yes: ") != "yes":
                    print("Removal cancelled")
                    return 0
            remove_client(secrets.Bitwarden(), args.host, args.name)
            return 0
        if not args.output or args.yes:
            raise ValueError("Creation requires an export directory; --yes is only for removal")
        output = args.output.expanduser().resolve()
        if output.exists():
            raise ValueError("Choose a new export directory; existing files are never overwritten")
        ancestor = output.parent
        while not ancestor.exists():
            ancestor = ancestor.parent
        check = subprocess.run(["git", "-C", str(ancestor), "rev-parse", "--is-inside-work-tree"],
                               capture_output=True, text=True)
        if check.returncode == 0:
            raise ValueError("Export outside Git repositories")
        vault = secrets.Bitwarden()
        config = prepare_client(vault, args.host, args.name, force=args.force)
        output.mkdir(mode=0o700, parents=True)
        secrets.write_private(output / f"{args.host}-{args.name}.conf", config)
        secrets.write_private(output / f"{args.host}-{args.name}.vpn", amnezia_link(config, f"{args.host}-{args.name}") + "\n")
        print(f"Client saved in Bitwarden and exported to {output}")
        deploy_server(vault, args.host)
        print(f"Server peer deployed. Import .conf into AmneziaWG or paste the .vpn link into AmneziaVPN. All IPv4 traffic uses {args.host}.")
        print("Server mode private blocks IPv4 Internet; full enables it. IPv6 is not routed by this profile.")
        return 0
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(str(error) if isinstance(error, ValueError) else "Client preparation failed; secret contents suppressed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
