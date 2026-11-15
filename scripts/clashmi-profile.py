#!/usr/bin/env python3
"""Synchronize the Bitwarden-provisioned subscription before Clash Mi starts."""

import json
import os
from pathlib import Path
import tempfile
from urllib.parse import urlsplit


def sync(home):
    subscription = home / ".config/pino/clashmi-subscription"
    if not subscription.is_file():
        return
    url = subscription.read_text().strip()
    parsed = urlsplit(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname or any(c.isspace() for c in url):
        raise ValueError("Invalid Clash Mi subscription URL")
    root = home / ".local/share/com.nebula.clashmi"
    target = root / "profiles.json"
    if target.is_symlink():
        raise ValueError("Clash Mi profile list is a symlink")
    config = json.loads(target.read_text()) if target.exists() else {"current_id": "", "profiles": []}
    if not isinstance(config, dict) or not isinstance(config.get("profiles"), list):
        raise ValueError("Invalid Clash Mi profile list")
    profile_id = "__pino_bitwarden__.yaml"
    matches = [p for p in config["profiles"] if isinstance(p, dict) and p.get("id") == profile_id]
    if len(matches) > 1 or (matches and matches[0].get("remark") != "Pino"):
        raise ValueError("Conflicting Clash Mi profile")
    if matches:
        profile = matches[0]
        if profile.get("url") == url:
            return
        profile["url"] = url
        profile["update"] = None
    else:
        config["profiles"].append({"id": profile_id, "remark": "Pino", "url": url,
                                   "update_interval": 3600})
        if not config.get("current_id"):
            config["current_id"] = profile_id
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=root, delete=False) as file:
            temporary = file.name
            os.fchmod(file.fileno(), 0o600)
            json.dump(config, file, ensure_ascii=False)
        os.replace(temporary, target)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    try:
        sync(Path.home())
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        print("Could not synchronize the Clash Mi subscription; check the Bitwarden note and app profile list.")
