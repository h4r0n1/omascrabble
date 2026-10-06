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
    game_id = a.new_invite({"gameLanguage": "fr", "timeMinutes": 20}, "Ana", TILES)
    b.new_join("Ben", TILES)
    pair.connect()
    # Someone used the link: they knock, and only the inviter lets them in.
    knock = pair.last(0, "knock")
    assert knock and knock["name"] == "Ben", pair.events[0]
    assert pair.last(1, "proposal") is None
    pair.command(0, {"cmd": "admit"})
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
        p.command(0, {"cmd": "admit"})
        p.command(1, {"cmd": "decline"})
        self.assertIsNotNone(p.last(0, "declined"))

    def test_turning_away_a_stranger(self):
        p = self.pair
        p.sides[0].new_invite({}, "Ana", TILES)
        p.sides[1].new_join("Mallory", TILES)
        p.connect()
        self.assertEqual(p.last(0, "knock")["name"], "Mallory")
        p.command(0, {"cmd": "turn-away"})
        self.assertIsNotNone(p.last(1, "turned-away"))
        self.assertIsNone(p.last(1, "proposal"), "a turned-away player never sees the game")
        self.assertEqual(p.sides[0].stage, "turned-away")
        # Admitting afterwards is refused.
        p.command(0, {"cmd": "admit"})
        self.assertIsNotNone(p.last(0, "error"))

    def test_a_call_to_a_friend_needs_no_knock(self):
        p = self.pair
        p.sides[0].new_invite({"gameLanguage": "en"}, "Ana", TILES, trusted=True)
        p.sides[1].new_join("Ben", TILES, auto_accept=True)
        p.connect()
        self.assertIsNone(p.last(0, "knock"))
        self.assertIsNotNone(p.last(0, "started"))
        self.assertIsNotNone(p.last(1, "started"))

    def test_settings_from_the_other_side_are_cleaned(self):
        c = S.clean_config({"gameLanguage": "en", "dictionary": "open-en", "timeMinutes": 25, "validation": "challenge",
                            "challengePenalty": "points", "evil": "x" * 9999, "mode": "human_vs_ai"})
        self.assertEqual(c, {"mode": "online", "gameLanguage": "en", "dictionary": "open-en", "timeMinutes": 25,
                             "validation": "challenge", "challengePenalty": "points"})
        self.assertEqual(S.clean_config({"dictionary": "../../etc", "timeMinutes": 999, "gameLanguage": "xx"}), {"mode": "online"})
        self.assertEqual(S.clean_config("nonsense"), {"mode": "online"})

    def test_names_from_the_other_side_are_cleaned(self):
        self.assertEqual(S.clean_name("Ben\u202e\x07 "), "Ben")
        self.assertEqual(len(S.clean_name("x" * 99)), 40)

    def test_nothing_beyond_the_knock_before_being_let_in(self):
        # The admission bypass reported in review: a forged deck4 while
        # knocking must not start (or save) anything.
        import json
        import deck as D
        p = self.pair
        a, b = p.sides[0], p.sides[1]
        a.new_invite({"gameLanguage": "fr"}, "Ana", TILES)
        a.precompute()
        b.new_join("Mallory", TILES)
        p.connect()
        self.assertEqual(a.stage, "knocking")
        forged = [format(pow(D.encode(i), 3, D.P), "x") for i in range(TILES)]
        for t, extra in (("deck4", {"values": forged}), ("deck2", {"values": forged}), ("commit", {"hash": "0" * 64}),
                         ("open", {"nonce": "00"}), ("keys", {"keys": {}}), ("accept", {}),
                         ("move", {"action": {"type": "pass", "player": 1}, "keys": {}, "claims": {}, "index": 0}),
                         ("audit", {"keys": {}}), ("rs2", {"values": forged})):
            before = dict(a.s)
            a.on_message(dict({"t": t, "seq": a.s["inSeq"] + 1}, **extra))
            self.assertEqual(a.stage, "knocking", t)
            self.assertEqual(json.load(open(a.path))["stage"], "knocking", t + " (saved)")
            self.assertEqual(a.s["inSeq"], before["inSeq"], t + ": a refused message changes nothing")
            self.assertIsNone(p.last(0, "started"), t)
            self.assertFalse(a.s.get("started") or a.s.get("admitted"), t)
        # Only the inviter's "Let in" opens the way.
        p.command(0, {"cmd": "admit"})
        self.assertTrue(a.s["admitted"])

    def test_messages_in_the_wrong_order_are_refused(self):
        p = self.pair
        game_id = start(p)
        a, b = p.sides[0], p.sides[1]
        # The game is playing: setup and handshake messages are no longer accepted.
        for side, t in ((1, "propose"), (0, "accept"), (1, "deck1"), (0, "deck4"), (1, "turned-away"), (0, "commit")):
            s = p.sides[side]
            stage = s.stage
            s.on_message({"t": t, "seq": s.s["inSeq"] + 1, "values": [], "config": {}, "hash": "0" * 64, "now": 0, "tiles": TILES})
            self.assertEqual(s.stage, stage, t)
            self.assertEqual(p.last(side, "error")["code"], "protocol", t)
        # And a command out of place is refused too.
        p.command(1, {"cmd": "admit"})
        self.assertEqual(p.last(1, "error")["code"], "command")

    def test_a_failed_message_leaves_no_trace(self):
        import json
        p = self.pair
        start(p)
        b = p.sides[1]
        before = json.load(open(b.path))
        # Valid until the last key: the first reveal would be recorded, then the
        # second fails; nothing of it may remain.
        b.on_message({"t": "move", "seq": b.s["inSeq"] + 1, "action": {"type": "play", "player": 0},
                      "keys": {"0": "2", "1": "zz"}, "claims": {"0": 1, "1": 2}, "index": 0})
        after = json.load(open(b.path))
        self.assertEqual(after["inSeq"], before["inSeq"])
        self.assertEqual(after["claims"], before["claims"])
        self.assertEqual(after["inbound"], before["inbound"])

    def test_hostile_shapes_never_crash_the_session(self):
        p = self.pair
        start(p)
        b = p.sides[1]
        for bad in ({"t": "keys", "keys": [1, 2]}, {"t": "move", "action": {}, "keys": "x", "claims": {}, "index": 0},
                    {"t": "move", "action": "x", "keys": {}, "claims": {}, "index": 0}, {"t": "audit", "keys": 5},
                    {"t": "open", "nonce": None}, {"t": "deck1", "values": "zz"}, {"t": "rs3", "values": [[]]}):
            bad["seq"] = b.s["inSeq"] + 1
            before = len(p.events[1])
            b.on_message(bad)  # must not raise
            self.assertEqual(p.events[1][-1].get("ev") if len(p.events[1]) > before else "error", "error", bad["t"])
        b.command({"cmd": "give", "handles": "nonsense"})
        b.command({"cmd": "move"})
        self.assertEqual(p.events[1][-1]["ev"], "error")

    def test_bad_messages_are_errors_not_crashes(self):
        p = self.pair
        start(p)
        p.sides[0].on_message({"t": "rs2", "seq": 999})
        p.sides[0].on_message("garbage")
        p.sides[0].on_message({"t": "nonsense", "seq": p.sides[0].s["inSeq"] + 1, "x": 1})
        self.assertIsNotNone(p.last(0, "error"))


if __name__ == "__main__":
    unittest.main()
