"""Tests for net/deck.py: a whole two-player game, then the ways to cheat.

    python3 -m unittest discover -s tests/net
"""

import os
import random
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "net"))

import deck as D  # noqa: E402

N = 102  # French set; the protocol doesn't care about letters


def setup_pair(n=N):
    a, b = D.Deck(n, 0), D.Deck(n, 1)
    s1 = a.setup_lock()
    s2 = b.setup_relock(s1)
    s3 = a.setup_personalise(s2)
    s4 = b.setup_personalise(s3)
    a.setup_finish(s4)
    return a, b


def draw(drawer, other, handle):
    return drawer.open(handle, other.share_key(handle))


def reveal(owner, viewer, handle):
    claim = owner.known[handle]
    return viewer.check_reveal(handle, owner.share_key(handle), claim)


def reshuffle(a, b, handles):
    x1 = a.reshuffle_strip(handles)
    x2 = b.reshuffle_strip_shuffle(handles, x1)
    x3 = a.reshuffle_shuffle_personalise(x2)
    x4, new_b = b.reshuffle_personalise(x3)
    new_a = a.reshuffle_finish(x4)
    assert new_a == new_b
    return new_a


class DeckTest(unittest.TestCase):
    def test_setup_gives_both_the_same_unreadable_deck(self):
        a, b = setup_pair()
        self.assertEqual(a.cards, b.cards)
        self.assertEqual(sorted(a.cards), list(range(N)))
        # Neither side can read a tile on its own.
        for h in range(N):
            self.assertNotIn(a.cards[h], a.table)

    def test_private_draws_and_public_reveals(self):
        a, b = setup_pair(30)
        rack_a = [draw(a, b, h) for h in range(7)]
        rack_b = [draw(b, a, h) for h in range(7, 14)]  # noqa
        drawn = rack_a + rack_b
        self.assertEqual(len(set(drawn)), 14, "every tile drawn once")
        # B knows nothing about A's rack until A plays a tile.
        self.assertTrue(all(h not in b.known for h in range(7)))
        self.assertEqual(reveal(a, b, 3), rack_a[3])
        self.assertEqual(b.known[3], rack_a[3])
        self.assertNotIn(2, b.known)

    def test_a_whole_game_with_exchanges_passes_the_audit(self):
        # A small bag keeps the test quick; the protocol doesn't depend on n.
        n = 40
        a, b = setup_pair(n)
        rng = random.Random(7)
        bag = list(range(n))
        racks = {0: [], 1: []}
        board, claims = [], {}
        sides = {0: (a, b), 1: (b, a)}

        def deal(p, count):
            me, other = sides[p]
            for _ in range(min(count, len(bag))):
                h = bag.pop(rng.randrange(len(bag)))
                draw(me, other, h)
                racks[p].append(h)

        deal(0, 7)
        deal(1, 7)
        turn = 0
        while bag:
            p = turn % 2
            me, other = sides[p]
            if turn % 5 == 4 and len(bag) >= 7:
                # Exchange three tiles: draw first, then return and reshuffle.
                give = racks[p][:3]
                racks[p] = racks[p][3:]
                deal(p, 3)
                order = bag + give
                new = reshuffle(a, b, order)
                bag[:] = new
            else:
                for h in racks[p][:2]:
                    claims[h] = reveal(me, other, h)
                board += racks[p][:2]
                racks[p] = racks[p][2:]
                deal(p, 7 - len(racks[p]))
            turn += 1
        in_play = board + racks[0] + racks[1] + bag
        for h in racks[0]:
            claims[h] = reveal(a, b, h)
        for h in racks[1]:
            claims[h] = reveal(b, a, h)
        result_a = a.audit(b.audit_keys(), in_play, claims)
        result_b = b.audit(a.audit_keys(), in_play, claims)
        self.assertEqual(result_a, result_b)
        self.assertEqual(sorted(result_a.values()), list(range(n)))

    def test_exchanged_tiles_cannot_be_followed(self):
        a, b = setup_pair(20)
        mine = [draw(a, b, h) for h in range(3)]
        new = reshuffle(a, b, list(range(3, 20)) + [0, 1, 2])
        self.assertEqual(len(new), 20)
        # The new handles are fresh, and A can't read any of them alone.
        self.assertTrue(min(new) >= 20)
        for h in new:
            self.assertNotIn(a.cards[h], a.table)
        # Drawing them all back still yields every tile once.
        seen = sorted(draw(a, b, h) for h in new)
        self.assertEqual(seen, list(range(20)))
        self.assertTrue(set(mine) <= set(seen))

    def test_false_claim_is_caught_at_once(self):
        a, b = setup_pair(10)
        real = draw(a, b, 0)
        with self.assertRaises(D.CheatDetected):
            b.check_reveal(0, a.share_key(0), (real + 1) % 10)

    def test_wrong_key_is_caught(self):
        a, b = setup_pair(10)
        with self.assertRaises(D.CheatDetected):
            a.open(0, b.share_key(1))

    def test_garbage_values_are_rejected(self):
        a, b = D.Deck(N, 0), D.Deck(N, 1)
        s1 = a.setup_lock()
        bad = list(s1)
        bad[5] = D.P - 1  # not in the subgroup
        with self.assertRaises(D.CheatDetected):
            b.setup_relock(bad)
        with self.assertRaises(D.CheatDetected):
            b.setup_relock(s1[:-1] + [s1[0]])  # a duplicate
        with self.assertRaises(D.ProtocolError):
            b.setup_relock(s1[:10])

    def test_a_doctored_bag_fails_the_audit(self):
        # A replaces one tile by a second copy of another at setup.
        n = 12
        a, b = D.Deck(n, 0), D.Deck(n, 1)
        a._global = D.new_key()
        e = a._global[0]
        doctored = [pow(D.encode(i), e, D.P) for i in range(n - 1)]
        # A different element encoding the same tile can't be made without
        # breaking the scheme, so a cheater must use a value that isn't a
        # real tile: here a random subgroup element.
        doctored.append(pow(D.encode(n + 40), e, D.P))
        s2 = b.setup_relock(doctored)
        s3 = a.setup_personalise(s2)
        s4 = b.setup_personalise(s3)
        a.setup_finish(s4)
        with self.assertRaises(D.CheatDetected):
            b.audit(a.audit_keys(), list(range(n)), {})

    def test_steps_belong_to_their_seat(self):
        a, b = D.Deck(N, 0), D.Deck(N, 1)
        with self.assertRaises(D.ProtocolError):
            b.setup_lock()
        with self.assertRaises(D.ProtocolError):
            a.setup_relock([])


if __name__ == "__main__":
    unittest.main()
