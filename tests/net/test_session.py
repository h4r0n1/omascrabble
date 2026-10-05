"""Tests for net/session.py: two sessions over an in-memory link.

    python3 -m unittest discover -s tests/net
"""

import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "net"))

import session as S  # noqa: E402

TILES = 16  # a small bag keeps the crypto quick; the protocol doesn't care


class Pair:
    """Two sessions and a link that can be cut."""

    def __init__(self, root):
        self.root = root
        self.queue = []
        self.events = {0: [], 1: []}
        self.up = True
        a = S.Session(os.path.join(root, "a", "invite.json"), lambda m: self._send(0, m), lambda e: self.events[0].append(e))
        b = S.Session(os.path.join(root, "b", "join.json"), lambda m: self._send(1, m), lambda e: self.events[1].append(e))
        self.sides = {0: a, 1: b}

    def _send(self, frm, msg):
        if self.up:
            self.queue.append((1 - frm, msg))

    def connect(self):
        self.up = True
        for side in (0, 1):
            self.sides[side].on_connected()
        self.pump()

    def cut(self):
        self.up = False
        for side in (0, 1):
            self.sides[side].on_disconnected()

    def pump(self):
        while self.queue:
            to, msg = self.queue.pop(0)
            # Round-trip through JSON like a real transport.
            import json
            self.sides[to].on_message(json.loads(json.dumps(msg)))

    def last(self, side, ev):
        for e in reversed(self.events[side]):
            if e.get("ev") == ev:
                return e
        return None

    def command(self, side, cmd):
        self.sides[side].command(cmd)
        self.pump()


def start(pair):
    a, b = pair.sides[0], pair.sides[1]
    game_id = a.new_invite({"lang": "fr", "time": 20}, "Ana", TILES)
    b.new_join("Ben", TILES)
    pair.connect()
    proposal = pair.last(1, "proposal")
    assert proposal and proposal["gameId"] == game_id
    pair.command(1, {"cmd": "accept"})
    return game_id


class SessionTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.pair = Pair(self.root)

    def tearDown(self):
        shutil.rmtree(self.root)

    def test_invitation_to_first_moves_to_audit(self):
        p = self.pair
        game_id = start(p)
        sa, sb = p.last(0, "started"), p.last(1, "started")
        self.assertIsNotNone(sa)
        self.assertIsNotNone(sb)
        for key in ("gameId", "seed", "first", "now", "names", "config"):
            self.assertEqual(sa[key], sb[key], key)
        self.assertEqual((sa["seat"], sb["seat"]), (0, 1))
        self.assertEqual(sa["names"], ["Ana", "Ben"])
        self.assertTrue(os.path.exists(os.path.join(self.root, "b", game_id + ".json")))
        # Racks: A gets handles 0-6, B 7-13.
        p.command(1, {"cmd": "give", "handles": list(range(7))})
        p.command(0, {"cmd": "give", "handles": list(range(7, 14))})
        p.command(0, {"cmd": "open", "handles": list(range(7))})
        p.command(1, {"cmd": "open", "handles": list(range(7, 14))})
        rack_a = p.last(0, "revealed")["tiles"]
        rack_b = p.last(1, "revealed")["tiles"]
        self.assertEqual(sorted(rack_a), [str(h) for h in range(7)])
        self.assertTrue(set(rack_a.values()).isdisjoint(rack_b.values()))
        # A plays two tiles; B learns exactly those.
        p.command(0, {"cmd": "move", "action": {"type": "play", "player": 0}, "reveal": [2, 5], "fp": "abc", "index": 0})
        act = p.last(1, "action")
        self.assertEqual(act["tiles"], {"2": rack_a["2"], "5": rack_a["5"]})
        self.assertEqual(act["fp"], "abc")
        # An exchange: both games ask for the same reshuffle.
        bag = [14, 15, 0, 1]
        p.command(1, {"cmd": "reshuffle", "handles": bag})
        p.command(0, {"cmd": "reshuffle", "handles": bag})
        ra, rb = p.last(0, "rebag"), p.last(1, "rebag")
        self.assertEqual(ra["handles"], rb["handles"])
        self.assertEqual(ra["handles"], list(range(TILES, TILES + 4)))
        # Asking again (a game restarted) gives the same answer.
        p.command(0, {"cmd": "reshuffle", "handles": bag})
        self.assertEqual(p.last(0, "rebag")["handles"], ra["handles"])
        # End: audit over everything in play.
        in_play = [2, 5, 3, 4, 6] + list(range(7, 14)) + ra["handles"]
        p.command(0, {"cmd": "audit", "inPlay": in_play})
        self.assertIsNone(p.last(0, "audited"))
        p.command(1, {"cmd": "audit", "inPlay": in_play})
        audited_a, audited_b = p.last(0, "audited"), p.last(1, "audited")
        self.assertEqual(audited_a["tiles"], audited_b["tiles"])
        self.assertEqual(sorted(audited_a["tiles"].values()), list(range(TILES)))
        self.assertIsNone(p.last(0, "cheat"))
        self.assertIsNone(p.last(1, "cheat"))

    def test_messages_sent_offline_arrive_after_reconnecting(self):
        p = self.pair
        start(p)
        p.cut()
        p.command(1, {"cmd": "give", "handles": list(range(7))})   # lost on the wire
        p.command(0, {"cmd": "open", "handles": list(range(7))})
        self.assertIsNone(p.last(0, "revealed"))
        p.connect()  # hello carries "have"; the log is resent
        self.assertEqual(len(p.last(0, "revealed")["tiles"]), 7)

    def test_a_restart_reloads_the_session(self):
        p = self.pair
        game_id = start(p)
        p.command(1, {"cmd": "give", "handles": [0, 1]})
        p.cut()
        # Helper A restarts from its file.
        path = os.path.join(self.root, "a", "invite.json")
        a2 = S.Session.load(path, lambda m: p._send(0, m), lambda e: p.events[0].append(e))
        self.assertEqual(a2.game_id, game_id)
        p.sides[0] = a2
        p.connect()
        p.command(0, {"cmd": "open", "handles": [0, 1]})
        self.assertEqual(len(p.last(0, "revealed")["tiles"]), 2)
        p.command(0, {"cmd": "move", "action": {"type": "pass", "player": 0}, "reveal": [], "fp": "f", "index": 0})
        self.assertEqual(p.last(1, "action")["action"]["type"], "pass")
        # The game restarted too and replays what it missed.
        p.events[1].clear()
        p.command(1, {"cmd": "resync", "moves": 0})
        self.assertEqual(p.last(1, "action")["index"], 0)

    def test_a_false_tile_is_reported(self):
        p = self.pair
        start(p)
        p.command(1, {"cmd": "give", "handles": [0]})
        p.command(0, {"cmd": "open", "handles": [0]})
        real = p.last(0, "revealed")["tiles"]["0"]
        a = p.sides[0]
        # A lies about the tile it plays.
        key = format(a.deck.share_key(0), "x")
        a._send({"t": "move", "action": {"type": "play", "player": 0}, "keys": {"0": key},
                 "claims": {"0": (real + 1) % TILES}, "fp": "x", "index": 0})
        p.pump()
        self.assertIsNotNone(p.last(1, "cheat"))

    def test_declining(self):
        p = self.pair
        p.sides[0].new_invite({}, "Ana", TILES)
        p.sides[1].new_join("Ben", TILES)
        p.connect()
        p.command(1, {"cmd": "decline"})
        self.assertIsNotNone(p.last(0, "declined"))

    def test_bad_messages_are_errors_not_crashes(self):
        p = self.pair
        start(p)
        p.sides[0].on_message({"t": "rs2", "seq": 999})
        p.sides[0].on_message("garbage")
        p.sides[0].on_message({"t": "nonsense", "seq": p.sides[0].s["inSeq"] + 1, "x": 1})
        self.assertIsNotNone(p.last(0, "error"))


if __name__ == "__main__":
    unittest.main()
