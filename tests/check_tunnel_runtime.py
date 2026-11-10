"""Run inside unshare -Urn. Test real TUN process routing using two veth paths.

Usage: python check_tunnel_runtime.py sing-box xray curl awg
No host routes, credentials or Internet endpoints are used.
"""
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("tunnel", ROOT / "scripts/tunnel.py")
tunnel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tunnel)


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def wait_for(check, process):
    for _ in range(100):
        if process.poll() is not None:
            raise AssertionError("Test process exited")
        if check():
            return
        time.sleep(.05)
    raise AssertionError("Test process did not become ready")


def main():
    mapping = Path("/proc/self/uid_map").read_text().split()
    assert mapping[:1] == ["0"] and mapping[-1:] == ["1"], "Run only inside unshare -Urn"
    sing, xray, curl, awg = sys.argv[1:]
    processes = []
    run("ip", "link", "set", "lo", "up")
    with tempfile.TemporaryDirectory(prefix="pino-tunnel-test-") as directory:
        root = Path(directory)
        ready = root / "ready"
        peer_script = root / "peer.py"
        peer_script.write_text('''
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import socket, threading, time, struct
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(self.client_address[0].encode())
    def log_message(self, *args): pass
while not Path("''' + str(ready) + '''").exists(): time.sleep(.05)
def dns():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("192.0.2.2", 53))
    while True:
        query, source = sock.recvfrom(4096)
        Path("''' + str(root / "dns-source") + '''").write_text(source[0])
        answer = query[:2] + bytes.fromhex("81800001000100000000") + query[12:]
        answer += bytes.fromhex("c00c000100010000003c0004c0000216")
        sock.sendto(answer, source)
threading.Thread(target=dns, daemon=True).start()
def udp_echo():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("192.0.2.2", 18081))
    while True:
        data, source = sock.recvfrom(4096)
        sock.sendto(source[0].encode(), source)
threading.Thread(target=udp_echo, daemon=True).start()
class Server6(HTTPServer): address_family = socket.AF_INET6
threading.Thread(target=Server6(("2001:db8::2", 18080), Handler).serve_forever, daemon=True).start()
HTTPServer(("192.0.2.2", 18080), Handler).serve_forever()
''')
        peer = subprocess.Popen(["unshare", "-n", sys.executable, str(peer_script)])
        processes.append(peer)
        try:
            time.sleep(.2)
            for name, subnet in (("wan0", "203.0.113"), ("vpn0", "198.51.100")):
                run("ip", "link", "add", name, "type", "veth", "peer", "name", name + "p")
                run("ip", "link", "set", name + "p", "netns", str(peer.pid))
                run("ip", "address", "add", subnet + ".1/24", "dev", name)
                run("ip", "link", "set", name, "up")
                run("nsenter", "-t", str(peer.pid), "-n", "ip", "address", "add", subnet + ".2/24", "dev", name + "p")
                run("nsenter", "-t", str(peer.pid), "-n", "ip", "link", "set", name + "p", "up")
            run("nsenter", "-t", str(peer.pid), "-n", "ip", "link", "set", "lo", "up")
            run("nsenter", "-t", str(peer.pid), "-n", "ip", "address", "add", "192.0.2.2/32", "dev", "lo")
            run("nsenter", "-t", str(peer.pid), "-n", "ip", "-6", "address", "add", "2001:db8::2/128", "dev", "lo", "nodad")
            for number, name in enumerate(("wan0", "vpn0"), 1):
                run("ip", "-6", "addr", "add", f"2001:db8:{number}::1/64", "dev", name, "nodad")
                run("nsenter", "-t", str(peer.pid), "-n", "ip", "-6", "addr", "add", f"2001:db8:{number}::2/64", "dev", name + "p", "nodad")
            run("ip", "-6", "route", "add", "default", "via", "2001:db8:1::2", "dev", "wan0")
            run("ip", "-6", "route", "add", "default", "via", "2001:db8:2::2", "dev", "vpn0", "table", "2025")
            run("ip", "-6", "rule", "add", "priority", "100", "fwmark", "2024", "lookup", "main")
            run("ip", "-6", "rule", "add", "priority", "101", "fwmark", "2025", "lookup", "2025")
            run("ip", "route", "add", "default", "via", "203.0.113.2", "dev", "wan0")
            run("ip", "route", "add", "default", "via", "198.51.100.2", "dev", "vpn0", "table", "2025")
            run("ip", "rule", "add", "priority", "100", "fwmark", "2024", "lookup", "main")
            run("ip", "rule", "add", "priority", "101", "fwmark", "2025", "lookup", "2025")
            # Exercise the actual AmneziaWG kernel driver using fixture keys.
            private_client = run(awg, "genkey").strip()
            private_server = run(awg, "genkey").strip()
            def pub(private):
                return subprocess.run([awg, "pubkey"], input=private + "\n", capture_output=True,
                                      text=True, check=True).stdout.strip()
            params = "Jc = 4\nJmin = 40\nJmax = 70\nS1 = 50\nS2 = 70\nH1 = 123456789\nH2 = 223456789\nH3 = 323456789\nH4 = 423456789\n"
            (root / "awg-client.conf").write_text("[Interface]\nPrivateKey = " + private_client + "\nFwMark = 2024\n" + params +
                "[Peer]\nPublicKey = " + pub(private_server) + "\nEndpoint = 203.0.113.2:585\nAllowedIPs = 0.0.0.0/0\n")
            (root / "awg-server.conf").write_text("[Interface]\nPrivateKey = " + private_server + "\nListenPort = 585\n" + params +
                "[Peer]\nPublicKey = " + pub(private_client) + "\nAllowedIPs = 10.77.0.2/32\n")
            run("ip", "link", "add", "awg-test", "type", "amneziawg")
            run(awg, "setconf", "awg-test", str(root / "awg-client.conf"))
            run("ip", "addr", "add", "10.77.0.2/24", "dev", "awg-test")
            run("ip", "link", "set", "awg-test", "mtu", "1280", "up")
            run("nsenter", "-t", str(peer.pid), "-n", "ip", "link", "add", "awg-peer", "type", "amneziawg")
            run("nsenter", "-t", str(peer.pid), "-n", awg, "setconf", "awg-peer", str(root / "awg-server.conf"))
            run("nsenter", "-t", str(peer.pid), "-n", "ip", "addr", "add", "10.77.0.1/24", "dev", "awg-peer")
            run("nsenter", "-t", str(peer.pid), "-n", "ip", "link", "set", "awg-peer", "mtu", "1280", "up")
            ready.touch()
            time.sleep(.2)
            # Use a real Xray SOCKS listener. Its transport takes the fixture VPN
            # path; the separate proxy integration test covers VLESS/XHTTP.
            proxy = {"log": {"loglevel": "none"}, "inbounds": [{"listen": "127.0.0.1", "port": 10808,
                     "protocol": "socks", "settings": {"udp": True}}],
                     "outbounds": [{"protocol": "freedom", "streamSettings": {
                         "sockopt": {"mark": 2025, "interface": "vpn0"}}}]}
            (root / "xray.json").write_text(json.dumps(proxy))
            xray_process = subprocess.Popen([xray, "run", "-config", str(root / "xray.json")], stdout=subprocess.DEVNULL)
            processes.append(xray_process)
            time.sleep(.2)
            for kind in ("awg", "xray"):
                if kind == "awg":
                    run("ip", "route", "replace", "default", "dev", "awg-test", "table", "2025")
                else:
                    run("ip", "route", "replace", "default", "via", "198.51.100.2", "dev", "vpn0", "table", "2025")
                vpn_source = "10.77.0.2" if kind == "awg" else "198.51.100.1"
                for default, exception in (("vpn", "direct"), ("direct", "vpn")):
                    config = tunnel.router_config(kind, "awg-test", "wan0", {"default": default, "apps": {"curl": exception}})
                    path = root / "router.json"
                    path.write_text(json.dumps(config))
                    run(sing, "check", "-c", str(path))
                    log = (root / "router.log").open("w")
                    router = subprocess.Popen([sing, "run", "-c", str(path)], stdout=log, stderr=log)
                    processes.append(router)
                    wait_for(lambda: subprocess.run(["ip", "link", "show", "pino-tun"], capture_output=True).returncode == 0, router)
                    time.sleep(.3)
                    direct_or_vpn = run(curl, "--noproxy", "*", "-fsS", "--max-time", "5", "http://192.0.2.2:18080/")
                    expected = "203.0.113.1" if exception == "direct" else vpn_source
                    assert direct_or_vpn == expected, (kind, default, "curl", direct_or_vpn)
                    # Python has no exception; it must take the default path.
                    sock = socket.create_connection(("192.0.2.2", 18080), timeout=5)
                    sock.sendall(b"GET / HTTP/1.0\r\nHost: fixture\r\n\r\n")
                    response = b""
                    while chunk := sock.recv(4096): response += chunk
                    sock.close()
                    expected = vpn_source.encode() if default == "vpn" else b"203.0.113.1"
                    assert response.endswith(expected), (kind, default, "python", response)
                    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    udp.settimeout(5)
                    udp.sendto(b"fixture", ("192.0.2.2", 18081))
                    response_udp, _ = udp.recvfrom(4096)
                    udp.close()
                    assert response_udp == expected, (kind, default, "UDP", response_udp)
                    # DNS must reach the requested server over the existing WAN path,
                    # without interception or a replacement DNS provider.
                    dns = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    dns.settimeout(5)
                    dns.sendto(bytes.fromhex("123401000001000000000000") + b"\x07example\x04test\x00\x00\x01\x00\x01", ("192.0.2.2", 53))
                    answer, _ = dns.recvfrom(4096)
                    dns.close()
                    assert answer[-4:] == bytes([192, 0, 2, 22]), "Existing DNS server unreachable"
                    assert (root / "dns-source").read_text() == "203.0.113.1", "DNS path changed"
                    ipv6 = subprocess.run([curl, "--noproxy", "*", "-gfsS", "--max-time", "3",
                                           "http://[2001:db8::2]:18080/"], capture_output=True, text=True)
                    if kind == "awg" and exception == "vpn":
                        assert ipv6.returncode != 0, "AWG app IPv6 escaped directly"
                    else:
                        expected6 = "2001:db8:1::1" if exception == "direct" else "2001:db8:2::1"
                        assert ipv6.returncode == 0 and ipv6.stdout == expected6, (kind, exception, ipv6)
                    sock6 = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
                    sock6.settimeout(3)
                    try:
                        sock6.connect(("2001:db8::2", 18080))
                        sock6.sendall(b"GET / HTTP/1.0\r\nHost: fixture\r\n\r\n")
                        response6 = b""
                        while chunk := sock6.recv(4096): response6 += chunk
                    except OSError:
                        assert kind == "awg" and default == "vpn", "Unexpected IPv6 failure"
                    else:
                        assert not (kind == "awg" and default == "vpn"), "AWG default IPv6 escaped directly"
                        expected6 = b"2001:db8:1::1" if default == "direct" else b"2001:db8:2::1"
                        assert response6.endswith(expected6), (kind, default, response6)
                    finally:
                        sock6.close()
                    router.terminate()
                    router.wait(timeout=15)
                    processes.remove(router)
                    log.close()
                    tunnel.cleanup_router()
                    if subprocess.run(["ip", "link", "show", "pino-tun"], capture_output=True).returncode == 0:
                        print(run("ip", "-j", "rule", "show"), flush=True)
                        print(run("ip", "-j", "link", "show", "pino-tun"), flush=True)
                        raise AssertionError("TUN cleanup failed")
                    print(f"PASS {kind}: default={default}, curl={exception}; process routes, system DNS path, IPv6, cleanup")
        finally:
            for process in reversed(processes):
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()
