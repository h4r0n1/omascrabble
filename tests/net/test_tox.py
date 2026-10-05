"""Two helpers over the real Tox network. Needs toxcore and the internet, so
it only runs when asked:

    OMASCRABBLE_TOX_TEST=1 python3 -m unittest tests/net/test_tox.py
"""

import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "net"))

import tox_transport  # noqa: E402
from test_helper import Proc, wait_for  # noqa: E402


@unittest.skipUnless(os.environ.get("OMASCRABBLE_TOX_TEST") == "1" and tox_transport.available(), "needs toxcore and OMASCRABBLE_TOX_TEST=1")
class ToxTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.procs = [Proc(os.path.join(self.root, "a"), "tox"), Proc(os.path.join(self.root, "b"), "tox")]

    def tearDown(self):
        for p in self.procs:
            p.close()
        shutil.rmtree(self.root)

    def test_invite_join_deal_move_resume_over_tox(self):
        a, b = self.procs
        a.send({"cmd": "hello", "name": "Ana"})
        b.send({"cmd": "hello", "name": "Ben"})
        self.assertEqual(wait_for(self.procs, 0, "ready")["transport"], "tox")
        a.send({"cmd": "invite", "config": {"gameLanguage": "en", "dictionary": "open-en"}})
        link = wait_for(self.procs, 0, "invite")["link"]
        self.assertTrue(link.startswith("omascrabble://tox/"))
        b.send({"cmd": "join", "link": link})
        proposal = wait_for(self.procs, 1, "proposal", timeout=180)
        self.assertEqual(proposal["from"], "Ana")
        b.send({"cmd": "accept"})
        sa = wait_for(self.procs, 0, "started", timeout=180)
        sb = wait_for(self.procs, 1, "started", timeout=180)
        self.assertEqual(sa["seed"], sb["seed"])
        a.send({"cmd": "give", "handles": list(range(7, 14))})
        b.send({"cmd": "give", "handles": list(range(7))})
        a.send({"cmd": "open", "handles": list(range(7))})
        b.send({"cmd": "open", "handles": list(range(7, 14))})
        rack_a = wait_for(self.procs, 0, "revealed", timeout=120)["tiles"]
        self.assertEqual(len(rack_a), 7)
        self.assertEqual(len(wait_for(self.procs, 1, "revealed", timeout=120)["tiles"]), 7)
        a.send({"cmd": "move", "action": {"type": "play", "player": 0}, "reveal": [0, 1], "fp": "fp1", "index": 0})
        act = wait_for(self.procs, 1, "action", timeout=120)
        self.assertEqual(act["tiles"], {"0": rack_a["0"], "1": rack_a["1"]})
        # B's helper dies; A moves; B comes back with the same Tox identity.
        b.close()
        a.send({"cmd": "move", "action": {"type": "pass", "player": 1}, "reveal": [], "fp": "fp2", "index": 1})
        b2 = Proc(os.path.join(self.root, "b"), "tox")
        self.procs[1] = b2
        b2.send({"cmd": "hello", "name": "Ben"})
        b2.send({"cmd": "resume", "gameId": sa["gameId"], "moves": 1})
        act2 = wait_for(self.procs, 1, "action", timeout=180)
        if act2["index"] < 1:  # a replay the game would ignore
            act2 = wait_for(self.procs, 1, "action", timeout=180, after=b2.events.index(act2) + 1)
        self.assertEqual(act2["fp"], "fp2")


    def test_friends_call_each_other_without_a_link(self):
        a, b = self.procs
        a.send({"cmd": "hello", "name": "Ana"})
        b.send({"cmd": "hello", "name": "Ben"})
        wait_for(self.procs, 0, "ready")
        # First game: by link. Both become friends.
        a.send({"cmd": "invite", "config": {"gameLanguage": "fr", "dictionary": "open-fr"}})
        link = wait_for(self.procs, 0, "invite")["link"]
        b.send({"cmd": "join", "link": link})
        wait_for(self.procs, 1, "proposal", timeout=180)
        b.send({"cmd": "accept"})
        wait_for(self.procs, 0, "started", timeout=180)
        wait_for(self.procs, 1, "started", timeout=180)
        friends_a = [e for e in a.events if e.get("ev") == "friends" and e["list"]][-1]["list"]
        friends_b = [e for e in b.events if e.get("ev") == "friends" and e["list"]][-1]["list"]
        self.assertEqual(friends_a[0]["name"], "Ben")
        self.assertEqual(friends_b[0]["name"], "Ana")
        ben = friends_a[0]["id"]
        # Second game: Ana calls Ben, no link.
        mark_a, mark_b = len(a.events), len(b.events)
        a.send({"cmd": "call", "friend": ben, "config": {"gameLanguage": "en", "dictionary": "open-en"}})
        call = wait_for(self.procs, 1, "call", timeout=120, after=mark_b)
        self.assertEqual(call["name"], "Ana")
        self.assertEqual(call["config"]["gameLanguage"], "en")
        b.send({"cmd": "answer", "friend": call["friend"], "accept": True})
        s2a = wait_for(self.procs, 0, "started", timeout=180, after=mark_a)
        s2b = wait_for(self.procs, 1, "started", timeout=180, after=mark_b)
        self.assertEqual(s2a["gameId"], s2b["gameId"])
        self.assertEqual(s2b["config"]["gameLanguage"], "en")
        # Third: Ben declines.
        mark_a, mark_b = len(a.events), len(b.events)
        a.send({"cmd": "call", "friend": ben, "config": {"gameLanguage": "fr"}})
        call = wait_for(self.procs, 1, "call", timeout=120, after=mark_b)
        b.send({"cmd": "answer", "friend": call["friend"], "accept": False})
        wait_for(self.procs, 0, "declined", timeout=120, after=mark_a)


if __name__ == "__main__":
    unittest.main()
