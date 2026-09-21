import importlib.util
from pathlib import Path
import subprocess
import unittest


spec = importlib.util.spec_from_file_location("connect", Path(__file__).resolve().parents[1] / "scripts/reaper-connect.py")
connect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(connect)


def node(number, name):
    return {"id": number, "type": "PipeWire:Interface:Node", "info": {"props": {"node.name": name}}}


def port(number, owner, name, direction):
    return {"id": number, "type": "PipeWire:Interface:Port", "info": {"props": {
        "node.id": owner, "port.name": name, "port.direction": direction}}}


def link(number, output, target):
    return {"id": number, "type": "PipeWire:Interface:Link", "info": {"props": {
        "link.output.port": output, "link.input.port": target}}}


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.graph = [node(1, "Focusrite"), node(2, "REAPER"), node(3, "Browser"),
                      port(11, 1, "capture", "out"), port(12, 1, "left", "in"), port(13, 1, "right", "in"),
                      port(21, 2, "in2", "in"), port(22, 2, "out1", "out"), port(23, 2, "out2", "out"),
                      port(31, 3, "out", "out")]
        self.routes = [{"output": "Focus*:capture", "input": "REAPER:in2", "replace": "input"},
                       {"output": "REAPER:out1", "input": "Focus*:left", "replace": "output"},
                       {"output": "REAPER:out2", "input": "Focus*:right", "replace": "output"}]

    def test_three_connections(self):
        additions, removals = connect.plan(self.graph, self.routes)
        self.assertEqual(set(additions), {("Focusrite:capture", "REAPER:in2"),
                                         ("REAPER:out1", "Focusrite:left"), ("REAPER:out2", "Focusrite:right")})
        self.assertEqual(removals, [])

    def test_repeat_is_noop_and_other_apps_are_preserved(self):
        self.graph += [link(101, 11, 21), link(102, 22, 12), link(103, 23, 13), link(104, 31, 12)]
        self.assertEqual(connect.plan(self.graph, self.routes), ([], []))

    def test_only_conflicting_reaper_links_are_removed(self):
        self.graph += [link(101, 31, 21), link(102, 22, 13), link(103, 31, 12)]
        _, removals = connect.plan(self.graph, self.routes)
        self.assertEqual(removals, [101, 102])

    def test_missing_or_ambiguous_port_prevents_changes(self):
        with self.assertRaises(ValueError):
            connect.plan(self.graph[:-1], self.routes + [{"output": "Browser:out", "input": "REAPER:in2", "replace": "input"}])
        self.graph += [node(4, "Focusrite-other"), port(41, 4, "capture", "out")]
        with self.assertRaises(ValueError):
            connect.plan(self.graph, self.routes)

    def test_failed_addition_rolls_back_without_removing_old_links(self):
        calls = []
        def run(command, check):
            calls.append(command)
            if command == ["pw-link", "missing", "input"]:
                raise subprocess.CalledProcessError(1, command)
        with self.assertRaises(subprocess.CalledProcessError):
            connect.apply([("output", "input"), ("missing", "input")], [999], run=run)
        self.assertEqual(calls[-1], ["pw-link", "-d", "output", "input"])
        self.assertNotIn(["pw-link", "-d", "999"], calls)


if __name__ == "__main__":
    unittest.main()
