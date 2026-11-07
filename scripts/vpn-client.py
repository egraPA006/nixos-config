#!/usr/bin/env python3
"""Create a full-IPv4 AWG client in Bitwarden and deploy its peer."""
import argparse
import copy
import importlib.util
import ipaddress
import os
from pathlib import Path
import re
import subprocess
import sys

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


def prepare_client(vault, host, name, force=False):
    if host != "mosk" or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,31}", name):
        raise ValueError("Use host mosk and a client name of 1–32 letters, digits, hyphens or underscores")
    server = vault.find(f"pino-vpn-server-{host}", 2)
    if not server:
        raise ValueError("Prepare the server Bitwarden note first")
    interface, peers = sections(server["notes"])
    address = ipaddress.IPv4Interface(interface["Address"])
    if address.network.prefixlen < 16:
        raise ValueError("VPN subnet is unexpectedly large")
    server_public = public_key(interface["PrivateKey"])
    item_name = f"pino-vpn-client-{name}-{host}"
    existing = vault.find(item_name, 2)
    used = [ipaddress.ip_network(value.strip()) for peer in peers
            for value in peer["AllowedIPs"].split(",")]
    if existing and not force:
        client, destinations = sections(existing["notes"])
        client_address = ipaddress.IPv4Interface(client["Address"])
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
            client, _ = sections(existing["notes"])
            private = client["PrivateKey"]
            public = public_key(private)
            old_address = ipaddress.IPv4Interface(client["Address"]).ip
            # Preserve the device key, so a failed vault update can be retried
            # without losing track of an old peer or revoking another device.
            used = [ipaddress.ip_network(value.strip()) for peer in peers
                    if peer.get("PublicKey") != public
                    for value in peer["AllowedIPs"].split(",")]
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
        config += (f"\n[Peer]\nPublicKey = {server_public}\n"
                   f"Endpoint = vpn.egrapa.com:{int(interface.get('ListenPort', '585'))}\n"
                   "AllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 25\n")
        matching = [peer for peer in peers if peer.get("PublicKey") == public]
        if len(matching) > 1:
            raise ValueError("Duplicate server peers for this device; resolve them first")
        if matching and matching[0].get("PresharedKey"):
            config += f"PresharedKey = {matching[0]['PresharedKey']}\n"
        # Save client first: a failed server edit is recoverable by rerunning.
        if existing:
            updated_client = copy.deepcopy(existing)
            updated_client["notes"] = config
            vault.edit(existing, updated_client)
        else:
            vault.create(item_name, 2, notes=config)
    matching = [p for p in peers if p.get("PublicKey") == public]
    if matching:
        if len(matching) != 1:
            raise ValueError("Existing server peer has a conflicting address")
        if matching[0].get("AllowedIPs") != str(client_address):
            if not force:
                raise ValueError("Existing server peer has a conflicting address; retry with --force")
            # Modify only this public key's peer block, preserving other peers,
            # comments and optional settings such as preshared keys.
            blocks = re.split(r"(?m)(?=^[ \t]*\[Peer\][ \t]*$)", server["notes"])
            for index in range(1, len(blocks)):
                _, entries = sections("[Interface]\n" + blocks[index])
                if entries[0].get("PublicKey") == public:
                    blocks[index] = re.sub(r"(?m)^\s*AllowedIPs\s*=.*$", f"AllowedIPs = {client_address}", blocks[index])
            updated = copy.deepcopy(server)
            updated["notes"] = "".join(blocks)
            vault.edit(server, updated)
    else:
        if any(client_address.ip in network for network in used):
            raise ValueError("Client address is already assigned to another peer")
        updated = copy.deepcopy(server)
        updated["notes"] = server["notes"].rstrip() + (
            f"\n\n[Peer]\n# {name}\nPublicKey = {public}\nAllowedIPs = {client_address}\n")
        vault.edit(server, updated)
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", choices=["mosk"])
    parser.add_argument("name")
    parser.add_argument("output", type=Path, help="New export directory outside Git")
    parser.add_argument("--force", action="store_true", help="Replace an existing Bitwarden client profile, preserving its device key; export directory must still be new")
    args = parser.parse_args()
    os.umask(0o077)
    try:
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
        print(f"Client saved in Bitwarden and exported to {output}")
        result = subprocess.run([
            "pino", "provision", "send", f"pino-vpn-server-{args.host}", args.host,
            "/etc/pino/vpn/awg0.conf", "amneziawg-server.service", "pino-vpn-mode.service",
        ], env=vault.env)
        if result.returncode:
            raise ValueError("Client saved, but deployment failed. Retry: pino provision host mosk")
        print("Server peer deployed. Import the .conf into AmneziaWG. All IPv4 traffic uses Mosk.")
        print("Server mode private blocks IPv4 Internet; full enables it. IPv6 is not routed by this profile.")
        return 0
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(str(error) if isinstance(error, ValueError) else "Client preparation failed; secret contents suppressed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
