#!/usr/bin/env python3
"""Create a private-network AWG client in Bitwarden and deploy its peer."""
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


def prepare_client(vault, host, name):
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
    if existing:
        client, destinations = sections(existing["notes"])
        client_address = ipaddress.IPv4Interface(client["Address"])
        if (len(destinations) != 1 or destinations[0].get("PublicKey") != server_public
                or destinations[0].get("AllowedIPs") != str(address.network)
                or client_address.network.prefixlen != 32
                or client_address.ip not in address.network
                or client_address.ip in (address.ip, address.network.network_address, address.network.broadcast_address)):
            raise ValueError("Existing client does not match this private server network; it was preserved")
        config = existing["notes"]
        public = public_key(client["PrivateKey"])
    else:
        candidate = next((ip for ip in address.network.hosts()
                          if ip != address.ip and not any(ip in network for network in used)), None)
        if candidate is None:
            raise ValueError("No available VPN client addresses")
        client_address = ipaddress.IPv4Interface(f"{candidate}/32")
        private = subprocess.run(["awg", "genkey"], capture_output=True, text=True, check=True).stdout.strip()
        public = public_key(private)
        # Copy only AWG protocol parameters, never server hooks or its private key.
        parameters = {key: value for key, value in interface.items()
                      if re.fullmatch(r"Jc|Jmin|Jmax|S[1-4]|H[1-4]|I[1-5]", key)}
        config = f"[Interface]\nPrivateKey = {private}\nAddress = {client_address}\n"
        config += "".join(f"{key} = {value}\n" for key, value in parameters.items())
        config += (f"\n[Peer]\nPublicKey = {server_public}\n"
                   f"Endpoint = vpn.egrapa.com:{int(interface.get('ListenPort', '585'))}\n"
                   f"AllowedIPs = {address.network}\nPersistentKeepalive = 25\n")
        # Save client first: a failed server edit is recoverable by rerunning.
        vault.create(item_name, 2, notes=config)
    matching = [p for p in peers if p.get("PublicKey") == public]
    if matching:
        if len(matching) != 1 or matching[0].get("AllowedIPs") != str(client_address):
            raise ValueError("Existing server peer has a conflicting address")
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
        config = prepare_client(vault, args.host, args.name)
        output.mkdir(mode=0o700, parents=True)
        secrets.write_private(output / f"{args.host}-{args.name}.conf", config)
        print(f"Client saved in Bitwarden and exported to {output}")
        result = subprocess.run([
            "pino", "provision", "send", f"pino-vpn-server-{args.host}", args.host,
            "/etc/pino/vpn/awg0.conf", "amneziawg-server.service", "pino-vpn-mode.service",
        ], env=vault.env)
        if result.returncode:
            raise ValueError("Client saved, but deployment failed. Retry: pino provision host mosk")
        print("Server peer deployed. Import the .conf into AmneziaWG. Access is private-network only.")
        return 0
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(str(error) if isinstance(error, ValueError) else "Client preparation failed; secret contents suppressed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
