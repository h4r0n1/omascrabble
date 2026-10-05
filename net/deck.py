"""Encrypted tile bag for a two-player game with no referee ("mental poker").

Neither machine ever knows the order of the bag, and each player learns a
tile's letter only when the rules allow it: their own draws, tiles played on
the board, racks shown at the end. Cheating (a false claim about a tile, a
doctored bag) is detected: false claims immediately, a doctored bag at the
latest by the end-of-game audit.

Construction: commutative ("SRA"/Pohlig-Hellman) encryption in the subgroup of
quadratic residues of the RFC 3526 1536-bit MODP safe prime p = 2q + 1. A tile
index i is encoded as (i + 2)^2 mod p, an element of that prime-order-q
subgroup; a key is an exponent e with inverse d = e^-1 mod q, so
(x^e)^d = x and locks from both players commute.

  setup      A locks every tile with a global key and shuffles; B does the
             same. Each then swaps its global lock for one key per position
             (still commutative), so a single tile can later be opened
             without exposing any other.
  draw       the non-drawing player sends its key for that one position; the
             drawer removes both locks and reads the tile.
  reveal     the owner publishes its key for a position; the other player
             removes both locks and checks the claimed tile.
  reshuffle  tiles a player has seen go back to the bag (exchange, withdrawn
             move): both strip their per-position keys under fresh global
             keys, both shuffle, both lock positions again. The bag gets new
             handles and nobody can follow a tile through it.
  audit      at the end every key is published; each side checks that every
             handle ever dealt decrypts to a real tile and that the tiles in
             play are each tile exactly once.

Every value received from the other side is checked to be a subgroup element
before use. Python standard library only. Messages are plain dicts of ints
and lists of ints; the caller serialises them (see helper).
"""

import hashlib
import math
import secrets

# RFC 3526, group 5 (1536-bit MODP). p is a safe prime. 1536 bits keeps a
# whole setup to a few seconds in pure Python (one exponentiation ~9 ms on a
# modest desktop, ~20 ms at 2048 bits) while staying far beyond what anyone
# would spend to peek at a Scrabble rack.
P = int(
    "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74"
    "020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F1437"
    "4FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
    "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF05"
    "98DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB"
    "9ED529077096966D670C354E4ABC9804F1746C08CA237327FFFFFFFFFFFFFFFF", 16)
Q = (P - 1) // 2


# Batch exponentiation hook: the helper installs a pool-backed version so a
# setup or reshuffle uses every core. Takes [(base, exponent)], returns
# [base^exponent mod p] in order.
POWMAP = None


def pow_mod(base, exponent):
    return pow(base, exponent, P)


def pow_all(pairs):
    if POWMAP is not None and len(pairs) > 8:
        return POWMAP(pairs)
    return [pow(b, e, P) for b, e in pairs]


class CheatDetected(Exception):
    """The other side sent something an honest player could not have sent."""


class ProtocolError(Exception):
    """A malformed or out-of-order message."""


def encode(index):
    return pow(index + 2, 2, P)


def new_key():
    """A random exponent and its inverse in the order-q subgroup."""
    while True:
        e = secrets.randbelow(Q - 2) + 2
        if math.gcd(e, Q) == 1:
            return e, pow(e, -1, Q)


def jacobi(a, n):
    """Jacobi symbol (a/n); for the prime p it is the Legendre symbol, so
    x is a quadratic residue (in the subgroup) exactly when it is 1. Far
    cheaper than x^q mod p."""
    a %= n
    result = 1
    while a:
        while a % 2 == 0:
            a //= 2
            if n % 8 in (3, 5):
                result = -result
        a, n = n, a
        if a % 4 == 3 and n % 4 == 3:
            result = -result
        a %= n
    return result if n == 1 else 0


def is_element(x):
    return isinstance(x, int) and 1 < x < P - 1 and jacobi(x, P) == 1


def check_elements(values, count, what):
    if not isinstance(values, list) or len(values) != count:
        raise ProtocolError("%s: expected %d values" % (what, count))
    for x in values:
        if not is_element(x):
            raise CheatDetected("%s: a value is not a valid encrypted tile" % what)
    if len(set(values)) != count:
        raise CheatDetected("%s: duplicate encrypted tiles" % what)


def check_key(k):
    if not isinstance(k, int) or not 1 < k < Q:
        raise ProtocolError("invalid key")


def shuffled(values):
    out = list(values)
    secrets.SystemRandom().shuffle(out)
    return out


def commitment(nonce):
    return hashlib.sha256(nonce).hexdigest()


class Deck:
    """One player's side of the bag. `seat` is 0 (A, starts every exchange of
    messages) or 1 (B). `tiles` is the number of tiles in the set."""

    def __init__(self, tiles, seat):
        if seat not in (0, 1):
            raise ValueError("seat must be 0 or 1")
        self.n = tiles
        self.seat = seat
        self.table = {encode(i): i for i in range(tiles)}
        self.cards = {}         # handle -> current doubly locked value
        self.keys = {}          # handle -> (e, d), my per-position keys
        self.retired = {}       # handle -> value, cards replaced by a reshuffle
        self.retired_keys = {}
        self.known = {}         # handle -> tile index, what I may know
        self.next_handle = 0
        self._global = None     # (e, d) during setup / reshuffle
        self._pending = None    # handles being reshuffled

    # ------------------------------------------------------------ setup
    def setup_lock(self):
        """A, step 1: every tile locked with A's global key, shuffled."""
        self._require_seat(0)
        self._global = new_key()
        e = self._global[0]
        return shuffled(pow_all([(encode(i), e) for i in range(self.n)]))

    def setup_relock(self, values):
        """B, step 2: lock again with B's global key, shuffle."""
        self._require_seat(1)
        check_elements(values, self.n, "setup")
        self._global = new_key()
        e = self._global[0]
        return shuffled(pow_all([(x, e) for x in values]))

    def setup_personalise(self, values):
        """Step 3 (A) then 4 (B): swap my global lock for one key per
        position. The last call's output is the final deck."""
        check_elements(values, self.n, "setup")
        return self._personalise(values, list(range(self.n)))

    def setup_finish(self, values):
        """A, after step 4: adopt the final deck."""
        self._require_seat(0)
        check_elements(values, self.n, "setup")
        self._adopt(values, list(range(self.n)))

    # ------------------------------------------------------------ draws
    def share_key(self, handle):
        """My key for one position, sent privately to the player drawing it,
        or publicly to reveal it."""
        if handle not in self.keys:
            raise ProtocolError("unknown handle %r" % handle)
        return self.keys[handle][1]

    def open(self, handle, other_key):
        """Read a tile with the other player's key for that position."""
        check_key(other_key)
        if handle not in self.cards:
            raise ProtocolError("unknown handle %r" % handle)
        value = pow(pow(self.cards[handle], other_key, P), self.keys[handle][1], P)
        index = self.table.get(value)
        if index is None:
            raise CheatDetected("the key for tile %d does not open it" % handle)
        if index in self.known.values() and self.known.get(handle) != index:
            raise CheatDetected("tile %d opened to a tile already in play" % handle)
        self.known[handle] = index
        return index

    def check_reveal(self, handle, other_key, claimed):
        """The owner played (or showed) a tile: check their claim."""
        index = self.open(handle, other_key)
        if index != claimed:
            raise CheatDetected("tile %d was claimed as %d but is %d" % (handle, claimed, index))
        return index

    # ------------------------------------------------------------ reshuffle
    # Order of messages: A.reshuffle_strip -> B.reshuffle_strip_shuffle ->
    # A.reshuffle_shuffle_personalise -> B.reshuffle_personalise ->
    # A.reshuffle_finish. `handles` is the agreed list (the bag after the
    # draw, plus the returned tiles), in the same order on both sides.
    def reshuffle_strip(self, handles):
        self._require_seat(0)
        self._begin_reshuffle(handles)
        e = self._global[0]
        return pow_all([(self.cards[h], (self.keys[h][1] * e) % Q) for h in handles])

    def reshuffle_strip_shuffle(self, handles, values):
        self._require_seat(1)
        self._begin_reshuffle(handles)
        check_elements(values, len(handles), "reshuffle")
        e = self._global[0]
        return shuffled(pow_all([(x, (self.keys[h][1] * e) % Q) for h, x in zip(handles, values)]))

    def reshuffle_shuffle_personalise(self, values):
        self._require_seat(0)
        count = self._pending_count()
        check_elements(values, count, "reshuffle")
        new = self._new_handles(count)
        return self._personalise(shuffled(values), new)

    def reshuffle_personalise(self, values):
        self._require_seat(1)
        count = self._pending_count()
        check_elements(values, count, "reshuffle")
        new = self._new_handles(count)
        out = self._personalise(values, new)
        self._retire(self._pending)
        return out, new

    def reshuffle_finish(self, values):
        self._require_seat(0)
        count = self._pending_count()
        check_elements(values, count, "reshuffle")
        new = list(range(self.next_handle - count, self.next_handle))
        self._adopt(values, new)
        self._retire(self._pending)
        return new

    # ------------------------------------------------------------ audit
    def audit_keys(self):
        """Every per-position key I ever used; publish only once the game is
        over."""
        out = {h: k[1] for h, k in self.retired_keys.items()}
        out.update({h: k[1] for h, k in self.keys.items()})
        return out

    def audit(self, other_keys, in_play, claims):
        """Check the whole game. `in_play`: handles on the board, in racks
        and in the bag at the end; `claims`: handle -> tile index for every
        tile either side ever revealed. Returns handle -> tile for in_play."""
        mine = self.audit_keys()
        everything = dict(self.retired)
        everything.update(self.cards)
        result = {}
        for h, value in everything.items():
            if h not in other_keys or h not in mine:
                raise CheatDetected("no key for tile %d" % h)
            check_key(other_keys[h])
            index = self.table.get(pow(pow(value, other_keys[h], P), mine[h], P))
            if index is None:
                raise CheatDetected("tile %d does not decrypt to a tile" % h)
            if h in claims and claims[h] != index:
                raise CheatDetected("tile %d was claimed as %d but is %d" % (h, claims[h], index))
            result[h] = index
        tiles = [result.get(h) for h in in_play]
        if None in tiles or sorted(tiles) != list(range(self.n)):
            raise CheatDetected("the tiles in play are not one of each tile")
        return {h: result[h] for h in in_play}

    # ------------------------------------------------------------ storage
    def to_json(self):
        """Everything needed to carry on after a restart. Contains secret
        keys: store it readable by the user only."""
        hx = lambda v: format(v, "x")
        pair = lambda k: [hx(k[0]), hx(k[1])]
        return {
            "n": self.n, "seat": self.seat, "next": self.next_handle,
            "cards": {str(h): hx(v) for h, v in self.cards.items()},
            "keys": {str(h): pair(k) for h, k in self.keys.items()},
            "retired": {str(h): hx(v) for h, v in self.retired.items()},
            "retiredKeys": {str(h): pair(k) for h, k in self.retired_keys.items()},
            "known": {str(h): i for h, i in self.known.items()},
            "global": pair(self._global) if self._global else None,
            "pending": self._pending,
        }

    @classmethod
    def from_json(cls, doc):
        num = lambda v: int(v, 16)
        deck = cls(int(doc["n"]), int(doc["seat"]))
        deck.next_handle = int(doc["next"])
        deck.cards = {int(h): num(v) for h, v in doc["cards"].items()}
        deck.keys = {int(h): (num(k[0]), num(k[1])) for h, k in doc["keys"].items()}
        deck.retired = {int(h): num(v) for h, v in doc["retired"].items()}
        deck.retired_keys = {int(h): (num(k[0]), num(k[1])) for h, k in doc["retiredKeys"].items()}
        deck.known = {int(h): int(i) for h, i in doc["known"].items()}
        deck._global = (num(doc["global"][0]), num(doc["global"][1])) if doc.get("global") else None
        deck._pending = list(doc["pending"]) if doc.get("pending") is not None else None
        return deck

    # ------------------------------------------------------------ internals
    def _require_seat(self, seat):
        if self.seat != seat:
            raise ProtocolError("this step belongs to the other player")

    def _personalise(self, values, handles):
        d = self._global[1]
        pairs = []
        for h, x in zip(handles, values):
            key = new_key()
            self.keys[h] = key
            pairs.append((x, (d * key[0]) % Q))
        out = pow_all(pairs)
        self._global = None
        if self.seat == 1:
            self._adopt(out, handles)
        return out

    def _adopt(self, values, handles):
        for h, x in zip(handles, values):
            self.cards[h] = x
        self.next_handle = max(self.next_handle, max(handles) + 1) if handles else self.next_handle

    def _begin_reshuffle(self, handles):
        if not isinstance(handles, list) or len(set(handles)) != len(handles) or not handles:
            raise ProtocolError("reshuffle: bad handle list")
        for h in handles:
            if h not in self.cards:
                raise ProtocolError("reshuffle: unknown handle %r" % h)
        self._pending = list(handles)
        self._global = new_key()

    def _pending_count(self):
        if self._pending is None:
            raise ProtocolError("no reshuffle in progress")
        return len(self._pending)

    def _new_handles(self, count):
        start = self.next_handle
        self.next_handle += count
        return list(range(start, start + count))

    def _retire(self, handles):
        for h in handles:
            self.retired[h] = self.cards.pop(h)
            self.retired_keys[h] = self.keys.pop(h)
            self.known.pop(h, None)
        self._pending = None
