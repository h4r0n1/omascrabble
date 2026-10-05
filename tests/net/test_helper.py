"""End-to-end: two real helper processes (net/online.py) over TCP on
localhost, driven the way two games drive them.

    python3 -m unittest discover -s tests/net
"""

import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HELPER = os.path.join(os.path.dirname(__file__), "..", "..", "net", "online.py")


class Proc:
    def __init__(self, state_dir, transport="tcp"):
        env = dict(os.environ, OMASCRABBLE_TRANSPORT=transport, OMASCRABBLE_TCP_PORT="0")
        self.state_dir = state_dir
        self.p = subprocess.Popen([sys.executable, HELPER, "--state-dir", state_dir], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, env=env)
        self.events = []
        self.buf = b""

    def send(self, cmd):
        self.p.stdin.write((json.dumps(cmd) + "\n").encode())
        self.p.stdin.flush()

    def pump(self, timeout=0.05):
        r, _, _ = select.select([self.p.stdout], [], [], timeout)
        if r:
            chunk = os.read(self.p.stdout.fileno(), 1 << 20)
            self.buf += chunk
            *lines, self.buf = self.buf.split(b"\n")
            for line in lines:
                if line.strip():
                    self.events.append(json.loads(line))

    def close(self):
        if self.p.poll() is None:
            self.p.kill()
        self.p.wait()
        self.p.stdin.close()
        self.p.stdout.close()


def wait_for(procs, side, ev, timeout=60, after=0):
    end = time.time() + timeout
    while time.time() < end:
        for p in procs:
            p.pump()
        for e in procs[side].events[after:]:
            if e.get("ev") == ev:
                return e
            if e.get("ev") in ("error", "cheat"):
                raise AssertionError("helper %d: %r" % (side, e))
    raise AssertionError("timed out waiting for %s on helper %d; got %r" % (ev, side, procs[side].events[-5:]))


class HelperTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.procs = [Proc(os.path.join(self.root, "a")), Proc(os.path.join(self.root, "b"))]

    def tearDown(self):
        for p in self.procs:
            p.close()
        shutil.rmtree(self.root)

    def test_two_helpers_play_and_survive_a_restart(self):
        a, b = self.procs
        a.send({"cmd": "hello", "name": "Ana"})
        b.send({"cmd": "hello", "name": "Ben"})
        self.assertEqual(wait_for(self.procs, 0, "ready")["transport"], "tcp")
        a.send({"cmd": "invite", "config": {"gameLanguage": "fr", "timeMinutes": 0}})
        invite = wait_for(self.procs, 0, "invite")
        self.assertTrue(invite["link"].startswith("omascrabble://tcp/127.0.0.1:"))
        b.send({"cmd": "join", "link": invite["link"], "tiles": 102})
        proposal = wait_for(self.procs, 1, "proposal")
        self.assertEqual(proposal["from"], "Ana")
        b.send({"cmd": "accept"})
        sa = wait_for(self.procs, 0, "started", timeout=120)
        sb = wait_for(self.procs, 1, "started", timeout=120)
        self.assertEqual(sa["seed"], sb["seed"])
        self.assertEqual(sa["gameId"], sb["gameId"])
        # Racks.
        a.send({"cmd": "give", "handles": list(range(7, 14))})
        b.send({"cmd": "give", "handles": list(range(7))})
        a.send({"cmd": "open", "handles": list(range(7))})
        b.send({"cmd": "open", "handles": list(range(7, 14))})
        rack_a = wait_for(self.procs, 0, "revealed")["tiles"]
        self.assertEqual(len(rack_a), 7)
        self.assertEqual(len(wait_for(self.procs, 1, "revealed")["tiles"]), 7)
        # A move, then helper B dies and comes back.
        a.send({"cmd": "move", "action": {"type": "play", "player": 0}, "reveal": [0, 1], "fp": "fp1", "index": 0})
        act = wait_for(self.procs, 1, "action")
        self.assertEqual(act["tiles"], {"0": rack_a["0"], "1": rack_a["1"]})
        b.close()
        a.send({"cmd": "move", "action": {"type": "pass", "player": 1}, "reveal": [], "fp": "fp2", "index": 1})
        b2 = Proc(os.path.join(self.root, "b"))
        self.procs[1] = b2
        b2.send({"cmd": "hello", "name": "Ben"})
        b2.send({"cmd": "resume", "gameId": sa["gameId"], "moves": 1})
        act2 = wait_for(self.procs, 1, "action")
        self.assertEqual(act2["fp"], "fp2")
        self.assertEqual(act2["index"], 1)
        # Session files are private.
        path = os.path.join(self.root, "b", "omascrabble", "online", sa["gameId"] + ".json")
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(os.path.dirname(path)).st_mode & 0o777, 0o700)

    def test_bad_link_and_missing_tox(self):
        a = self.procs[0]
        a.send({"cmd": "hello", "name": "Ana"})
        wait_for(self.procs, 0, "ready")
        a.send({"cmd": "join", "link": "https://example.com"})
        end = time.time() + 5
        while time.time() < end and not any(e.get("ev") == "error" for e in a.events):
            a.pump()
        self.assertTrue(any(e.get("ev") == "error" and e.get("code") == "link" for e in a.events))


if __name__ == "__main__":
    unittest.main()


class NoBytecodeTest(unittest.TestCase):
    """The helper runs from the plugin folder, which Omarchy watches: it must
    never write __pycache__ there (that reloads the plugin and closes the
    game)."""

    def test_helper_leaves_its_folder_untouched(self):
        root = tempfile.mkdtemp()
        try:
            net = os.path.join(root, "net")
            shutil.copytree(os.path.dirname(HELPER), net, ignore=shutil.ignore_patterns("__pycache__"))
            env = dict(os.environ, OMASCRABBLE_TRANSPORT="tcp")
            env.pop("PYTHONDONTWRITEBYTECODE", None)
            # Exactly how the game starts it would add -B; check the helper
            # protects itself even without it.
            p = subprocess.run([sys.executable, os.path.join(net, "online.py"), "--state-dir", os.path.join(root, "state")],
                               input=b'{"cmd":"hello","name":"x"}\n{"cmd":"invite","config":{}}\n{"cmd":"quit"}\n',
                               capture_output=True, env=env, timeout=60)
            self.assertIn(b'"ev":"invite"', p.stdout)
            written = [f for f in os.listdir(net) if f == "__pycache__" or f.endswith(".pyc")]
            self.assertEqual(written, [])
        finally:
            shutil.rmtree(root)
