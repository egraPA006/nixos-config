"""Offline integration check. Run ONLY inside unshare -Urn, with built binaries.

Arguments: xray-binary telemt-binary caddy-binary generated-Caddyfile
Uses public documentation IPs inside the isolated namespace, never the Internet.
"""
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("proxy", ROOT / "scripts/proxy-config.py")
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


def ready(process, address):
    for _ in range(100):
        if process.poll() is not None:
            raise AssertionError("Test service exited before listening")
        try:
            with socket.create_connection(address, timeout=.1):
                return
        except OSError:
            time.sleep(.1)
    raise AssertionError("Test service did not listen")


class Page(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"pino-runtime-fixture")

    def log_message(self, *args):
        pass


def main():
    mapping = Path("/proc/self/uid_map").read_text().split()
    if len(mapping) != 3 or mapping[0] != "0" or mapping[2] != "1":
        raise SystemExit("Use an isolated network namespace: unshare -Urn")
    xray, telemt, caddy, caddyfile = sys.argv[1:]
    subprocess.run(["ip", "link", "set", "lo", "up"], check=True)
    for address in ("203.0.113.1/32", "203.0.113.2/32"):
        subprocess.run(["ip", "addr", "add", address, "dev", "lo"], check=True)
    processes = []
    with tempfile.TemporaryDirectory(prefix="pino-runtime-") as directory:
        root = Path(directory)

        def start(binary, args, filename, contents, address):
            config = root / filename
            config.write_text(contents)
            process = subprocess.Popen([binary, *args, str(config)], cwd=root,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       env=dict(os.environ, HOME=str(root), XDG_DATA_HOME=str(root)))
            processes.append(process)
            ready(process, address)

        server = ThreadingHTTPServer(("0.0.0.0", 18090), Page)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            identifier = "12345678-1234-4234-8234-123456789abc"
            server_config = proxy.render("xray", {"port": 10080, "path": "/pino-xhttp"},
                                         {"users": {"fixture": identifier}})
            check = root / "check.json"
            check.write_text(server_config)
            subprocess.run([xray, "run", "-test", "-config", str(check)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            start(xray, ["run", "-config"], "server.json", server_config, ("127.0.0.1", 10080))
            start(telemt, [], "telemt.toml", proxy.render("telemt", {
                "port": 2443, "tlsDomain": "www.microsoft.com",
            }, {"users": {"fixture": "123456789abcdef0123456789abcdef0"}}), ("127.0.0.1", 2443))
            adapted = subprocess.run([caddy, "adapt", "--config", caddyfile, "--adapter", "caddyfile"],
                                     check=True, capture_output=True, text=True)
            config = json.loads(adapted.stdout)
            # Keep production routes; remove TLS/ACME and move logs for this
            # offline HTTP transport check. Real certificates need live DNS.
            config.get("apps", {}).pop("tls", None)
            for settings in config["apps"]["http"]["servers"].values():
                settings["listen"] = ["203.0.113.1:18080"]
                settings["automatic_https"] = {"disable": True}
                settings.pop("tls_connection_policies", None)
            for name, logger in config.get("logging", {}).get("logs", {}).items():
                if logger.get("writer", {}).get("output") == "file":
                    logger["writer"]["filename"] = str(root / (name + ".log"))
            start(caddy, ["run", "--config"], "caddy.json", json.dumps(config), ("203.0.113.1", 18080))

            def request(address, path, host=None, source=None):
                connection = http.client.HTTPConnection(*address, timeout=5, source_address=source)
                try:
                    connection.request("GET", path, headers={"Host": host} if host else {})
                    response = connection.getresponse()
                    return response.status, response.read()
                finally:
                    connection.close()

            status, body = request(("203.0.113.1", 18080), "/", "egrapa.com")
            assert status == 200 and b"Mosk" in body, "Website route is broken"
            status, _ = request(("203.0.113.1", 18080), "/pino-xhttp", "egrapa.com", ("127.0.0.1", 0))
            assert status == 403, "Private VPN clients must not access Xray through Caddy"

            client = {
                "log": {"loglevel": "none"},
                "inbounds": [{"listen": "127.0.0.1", "port": 18088, "protocol": "http"}],
                "outbounds": [{"protocol": "vless", "settings": {"vnext": [{
                    "address": "203.0.113.1", "port": 18080,
                    "users": [{"id": identifier, "encryption": "none"}],
                }]}, "streamSettings": {"network": "xhttp", "security": "none",
                    "xhttpSettings": {"host": "egrapa.com", "path": "/pino-xhttp", "mode": "auto"}}}],
            }
            start(xray, ["run", "-config"], "client.json", json.dumps(client), ("127.0.0.1", 18088))
            status, body = request(("127.0.0.1", 18088), "http://203.0.113.2:18090/")
            assert status == 200 and body == b"pino-runtime-fixture", "XHTTP forwarding failed"
            try:
                status, body = request(("127.0.0.1", 18088), "http://127.0.0.1:18090/")
            except (OSError, http.client.HTTPException):
                pass
            else:
                assert body != b"pino-runtime-fixture", "Private backend leaked through Xray"
            print("PASS: telemt startup, website, private-source rejection, XHTTP forwarding, private-destination rejection")
        finally:
            server.shutdown()
            server.server_close()
            for process in reversed(processes):
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()
