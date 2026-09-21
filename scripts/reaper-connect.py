#!/usr/bin/env python3
"""Connect declared REAPER ports using the current PipeWire graph."""

import argparse
import fnmatch
import json
from pathlib import Path
import subprocess
import sys


def plan(graph, routes):
    nodes = {o["id"]: o.get("info", {}).get("props", {}).get("node.name", "")
             for o in graph if o["type"] == "PipeWire:Interface:Node"}
    ports = {}
    links = []
    for obj in graph:
        props = obj.get("info", {}).get("props", {})
        if obj["type"] == "PipeWire:Interface:Port":
            node = nodes.get(int(props.get("node.id", -1)), "")
            if node and "port.name" in props:
                ports[obj["id"]] = (f'{node}:{props["port.name"]}', props.get("port.direction"))
        elif obj["type"] == "PipeWire:Interface:Link":
            links.append((obj["id"], int(props["link.output.port"]), int(props["link.input.port"])))

    def select(pattern, direction):
        matches = [port for port, (name, way) in ports.items()
                   if way == direction and fnmatch.fnmatchcase(name.casefold(), pattern.casefold())]
        if len(matches) != 1:
            raise ValueError(f"Expected one {direction} port matching {pattern!r}, found {len(matches)}. "
                             "Open REAPER with JACK and the Focusrite connected; inspect ports with pw-link -io.")
        return matches[0]

    desired = set()
    replace_inputs, replace_outputs = set(), set()
    for route in routes:
        output = select(route["output"], "out")
        target = select(route["input"], "in")
        desired.add((output, target))
        if route["replace"] == "input":
            replace_inputs.add(target)
        else:
            replace_outputs.add(output)
    if not desired:
        raise ValueError("No REAPER connections are configured")
    existing = {(output, target) for _, output, target in links}
    additions = [(ports[o][0], ports[i][0]) for o, i in sorted(desired - existing)]
    removals = [link for link, o, i in links
                if (i in replace_inputs or o in replace_outputs) and (o, i) not in desired]
    return additions, removals


def apply(additions, removals, run=subprocess.run):
    created = []
    try:
        for output, target in additions:
            run(["pw-link", output, target], check=True)
            created.append((output, target))
    except subprocess.CalledProcessError:
        # Keep the old routing intact if a requested new port disappears.
        for output, target in reversed(created):
            run(["pw-link", "-d", output, target], check=False)
        raise
    for link in removals:
        run(["pw-link", "-d", str(link)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    routes = json.loads(Path(args.config).read_text())
    graph = json.loads(subprocess.run(["pw-dump"], check=True, capture_output=True, text=True).stdout)
    additions, removals = plan(graph, routes)
    for output, target in additions:
        print(f"Connect: {output} -> {target}")
    for link in removals:
        print(f"Replace conflicting REAPER link: {link}")
    if args.dry_run:
        print("Dry run: routing unchanged.")
    else:
        apply(additions, removals)
        print("Guitar input and REAPER stereo output are connected.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"REAPER connection failed: {error}", file=sys.stderr)
        sys.exit(1)
