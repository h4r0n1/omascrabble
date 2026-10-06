"""One online game between two machines, with no referee.

The session is the protocol between the two helpers: invitation handshake,
game proposal, the seed (commit-reveal), dealing the encrypted bag
(net/deck.py), private draws, moves with checked tiles, reshuffles and the
end-of-game audit. It knows nothing about the network (a transport hands it
messages and sends what it returns) nor about Scrabble rules (the game, on
each machine, applies every move with the same engine).

Every game message carries a sequence number and is kept in an outbound log;
on (re)connection each side says how far it got and the other resends the
rest. The session is saved after every change, so a restart picks up where
it left off. The saved file holds secret keys and is readable by the user
only.

Messages to the game (emit) and from it (command) are dicts; see
docs/ONLINE.md for the list.
"""

import hashlib
import json
import os
import re
import secrets
import tempfile
import time

from deck import Deck, CheatDetected, ProtocolError, commitment

PROTOCOL = 1
MAX_LOG = 5000

# Which side may receive each message, and in which stages. Anything else is
# refused before it can change the session: in particular nothing beyond the
# knock is accepted from someone the inviter hasn't let in.
ANY = ("inviter", "joiner")
MESSAGES = {
    "propose": (("joiner",), ("joining",)),
    "turned-away": (("joiner",), ("joining",)),
    "accept": (("inviter",), ("proposed",)),
    "decline": (("inviter",), ("proposed",)),
    "commit": (ANY, ("seeding",)),
    "open": (ANY, ("seeding",)),
    "deck1": (("joiner",), ("dealing",)),
    "deck2": (("inviter",), ("dealing",)),
    "deck3": (("joiner",), ("dealing",)),
    "deck4": (("inviter",), ("dealing",)),
    "keys": (ANY, ("playing", "ended")),
    "move": (ANY, ("playing",)),
    "rs1": (("joiner",), ("playing",)),
    "rs2": (("inviter",), ("playing",)),
    "rs3": (("joiner",), ("playing",)),
    "rs4": (("inviter",), ("playing",)),
    "audit": (ANY, ("playing", "ended")),
    "bye": (ANY, None),
}
COMMANDS = {
    "admit": ("knocking",), "turn-away": ("knocking",),
    "accept": ("proposed",), "decline": ("proposed",),
    "give": ("playing",), "open": ("playing",), "move": ("playing",), "reshuffle": ("playing",),
    "audit": ("playing", "ended"), "resync": None, "bye": None,
}

# Control characters and bidirectional overrides (which can make a name read
# as something else) never survive in a name from the other machine.
_UNSAFE = re.compile("[\x00-\x1f\x7f-\x9f\u200e\u200f\u202a-\u202e\u2066-\u2069]")


def clean_name(value):
    return _UNSAFE.sub("", str(value)).strip()[:40]


_DICTIONARY_ID = re.compile(r"^[a-z0-9-]{1,32}$")


def clean_config(config):
    """Game settings from the other machine (or a friend's call): only the
    known keys, each with an allowed value."""
    c = config if isinstance(config, dict) else {}
    out = {"mode": "online"}
    if c.get("gameLanguage") in ("fr", "en"):
        out["gameLanguage"] = c["gameLanguage"]
    if isinstance(c.get("dictionary"), str) and _DICTIONARY_ID.match(c["dictionary"]):
        out["dictionary"] = c["dictionary"]
    if c.get("timeMinutes") in (0, 10, 20, 25, 30):
        out["timeMinutes"] = c["timeMinutes"]
    if c.get("validation") in ("immediate", "challenge"):
        out["validation"] = c["validation"]
    if c.get("challengePenalty") in ("none", "points", "lose_turn"):
        out["challengePenalty"] = c["challengePenalty"]
    return out


class Session:
    def __init__(self, path, send, emit):
        self.path = path
        self._send_raw = send       # dict -> peer
        self._emit_raw = emit       # dict -> game
        self.connected = False
        self.s = None               # the persisted state (a plain dict)
        self.deck = None

    # ------------------------------------------------------------ lifecycle
    def new_invite(self, config, name, tiles, trusted=False):
        """`trusted`: a call to a known friend, who doesn't need letting in.
        Anyone else arriving with the invitation secret knocks first: the
        inviter sees their name and safety code and admits or turns them
        away (a leaked link alone never lets anyone in)."""
        self.s = self._blank("inviter", 0, name, tiles)
        self.s["id"] = secrets.token_hex(8)
        self.s["config"] = clean_config(config)
        self.s["trusted"] = bool(trusted)
        self.s["stage"] = "inviting"
        self.s["now"] = int(time.time() * 1000)
        self._save()
        return self.s["id"]

    def precompute(self):
        """Inviter: lock and shuffle the bag now, while waiting for the
        friend, so dealing starts at once when they accept."""
        if self.s["seat"] != 0 or self.s.get("deck1") or self.deck is not None:
            return
        self.deck = Deck(self.s["tiles"], 0)
        self.s["deck1"] = _hex(self.deck.setup_lock())
        self._save()

    def new_join(self, name, tiles, auto_accept=False):
        """`auto_accept`: the player already accepted (a friend's call), so
        the proposal is accepted as soon as it arrives."""
        self.s = self._blank("joiner", 1, name, tiles)
        self.s["stage"] = "joining"
        self.s["autoAccept"] = bool(auto_accept)
        self._save()

    def _emit(self, event):
        # Save first: once the game has seen an event, a restart must not
        # replay the message that caused it.
        self._save()
        self._emit_raw(event)

    @classmethod
    def load(cls, path, send, emit):
        session = cls(path, send, emit)
        with open(path, encoding="utf-8") as f:
            session.s = json.load(f)
        if session.s.get("deck"):
            session.deck = Deck.from_json(session.s["deck"])
        return session

    @property
    def game_id(self):
        return self.s.get("id") if self.s else None

    @property
    def stage(self):
        return self.s.get("stage") if self.s else None

    # ------------------------------------------------------------ transport side
    def on_connected(self):
        self.connected = True
        self._send_raw({"t": "hello", "v": PROTOCOL, "session": self.s.get("id"), "name": self.s["name"], "have": self.s["inSeq"]})
        self._emit({"ev": "link", "state": "connected"})

    def on_disconnected(self):
        self.connected = False
        self._emit({"ev": "link", "state": "disconnected"})

    def _snapshot(self):
        return json.dumps(self.s), (self.deck.to_json() if self.deck is not None else None)

    def _restore(self, snapshot):
        self.s = json.loads(snapshot[0])
        self.deck = Deck.from_json(snapshot[1]) if snapshot[1] is not None else None

    def on_message(self, msg):
        """A message from the other helper. Returns nothing; problems are
        reported to the game (cheat / error events). A message is applied
        completely or not at all: if it fails, the session is restored to
        what it was before it, on disk too."""
        snapshot = self._snapshot()
        try:
            if not isinstance(msg, dict) or not isinstance(msg.get("t"), str):
                raise ProtocolError("malformed message")
            if msg["t"] == "hello":
                self._on_hello(msg)
                return
            seq = msg.get("seq")
            if not isinstance(seq, int):
                raise ProtocolError("message without a sequence number")
            if seq <= self.s["inSeq"]:
                return  # already processed (resent after a reconnection)
            if seq != self.s["inSeq"] + 1:
                # A gap: ask for a resend from where we are.
                self._send_raw({"t": "hello", "v": PROTOCOL, "session": self.s.get("id"), "name": self.s["name"], "have": self.s["inSeq"]})
                return
            rule = MESSAGES.get(msg["t"])
            if rule is None:
                raise ProtocolError("unknown message %r" % msg["t"])
            roles, stages = rule
            if self.s["role"] not in roles or (stages is not None and self.s["stage"] not in stages):
                raise ProtocolError("message %r not allowed now" % msg["t"])
            self.s["inSeq"] = seq
            getattr(self, "_on_" + msg["t"].replace("-", "_"))(msg)
            self._save()
        except CheatDetected as e:
            self._restore(snapshot)
            self.s["stage"] = "invalid"
            self._save()
            self._emit({"ev": "cheat", "message": str(e)})
        except Exception as e:  # malformed or hostile input must never stop the helper
            self._restore(snapshot)
            self._save()
            self._emit({"ev": "error", "code": "protocol", "message": str(e)})

    # ------------------------------------------------------------ game side
    def command(self, cmd):
        snapshot = self._snapshot()
        try:
            name = cmd.get("cmd")
            if name not in COMMANDS:
                raise ProtocolError("unknown command %r" % name)
            stages = COMMANDS[name]
            if stages is not None and self.s["stage"] not in stages:
                raise ProtocolError("command %r not allowed now" % name)
            getattr(self, "_cmd_" + str(name).replace("-", "_"))(cmd)
            self._save()
        except CheatDetected as e:
            self._restore(snapshot)
            self.s["stage"] = "invalid"
            self._save()
            self._emit({"ev": "cheat", "message": str(e)})
        except Exception as e:  # malformed or hostile input must never stop the helper
            self._restore(snapshot)
            self._save()
            self._emit({"ev": "error", "code": "command", "message": str(e)})

    # ------------------------------------------------------------ handshake
    def _on_hello(self, msg):
        if msg.get("v") != PROTOCOL:
            self._emit({"ev": "error", "code": "version", "message": "the other player runs an incompatible version"})
            return
        if not isinstance(msg.get("name"), str) or not isinstance(msg.get("have"), int):
            raise ProtocolError("bad hello")
        self.s["peerName"] = clean_name(msg["name"])
        if self.s["role"] == "joiner" and self.s.get("id") is None and isinstance(msg.get("session"), str):
            self._adopt_id(msg["session"])
        elif msg.get("session") not in (None, self.s.get("id")):
            raise ProtocolError("hello for another game")
        # Resend whatever the other side hasn't processed yet.
        for m in self.s["outLog"]:
            if m["seq"] > msg["have"]:
                self._send_raw(m)
        knock = False
        if self.s["role"] == "inviter" and self.s["stage"] == "inviting":
            if self.s.get("trusted"):
                self._propose()
            else:
                self.s["stage"] = "knocking"
                knock = True
        elif self.s["role"] == "inviter" and self.s["stage"] == "knocking":
            knock = True  # reconnected while waiting to be let in
        self._emit({"ev": "peer", "name": self.s["peerName"], "gameId": self.s.get("id")})
        if knock:
            self._emit({"ev": "knock", "name": self.s["peerName"], "gameId": self.s.get("id")})
        self._save()

    def _propose(self):
        # Proposing is the inviter's consent: a trusted friend's call, or
        # "Let in". No game can start without it.
        self.s["admitted"] = True
        self.s["stage"] = "proposed"
        self._send({"t": "propose", "game": self.s["id"], "config": self.s["config"], "now": self.s["now"],
                    "name": self.s["name"], "tiles": self.s["tiles"]})

    def _cmd_admit(self, cmd):
        if self.s["role"] != "inviter" or self.s["stage"] != "knocking":
            raise ProtocolError("nobody is waiting to be let in")
        self._propose()

    def _cmd_turn_away(self, cmd):
        if self.s["role"] != "inviter" or self.s["stage"] != "knocking":
            raise ProtocolError("nobody is waiting to be let in")
        self.s["stage"] = "turned-away"
        self._send({"t": "turned-away"})

    def _on_turned_away(self, msg):
        if self.s["role"] != "joiner":
            raise ProtocolError("unexpected message")
        self.s["stage"] = "declined"
        self._emit({"ev": "turned-away"})

    def _on_propose(self, msg):
        if self.s["role"] != "joiner":
            raise ProtocolError("unexpected proposal")
        if not isinstance(msg.get("config"), dict):
            raise ProtocolError("bad proposal")
        msg["config"] = clean_config(msg["config"])
        tiles = int(msg.get("tiles", 0))
        if not 2 <= tiles <= 200:
            raise ProtocolError("bad tile count")
        self.s["config"] = msg["config"]
        self.s["tiles"] = tiles
        self.s["now"] = int(msg["now"])
        self.s["stage"] = "proposed"
        self._emit({"ev": "proposal", "config": msg["config"], "from": self.s.get("peerName", ""), "gameId": self.s["id"],
                    "autoAccept": bool(self.s.get("autoAccept"))})
        if self.s.get("autoAccept"):
            self._cmd_accept({})

    def _cmd_accept(self, cmd):
        if self.s["role"] != "joiner" or self.s["stage"] != "proposed":
            raise ProtocolError("nothing to accept")
        self.s["admitted"] = True  # the joiner consents by accepting
        self.s["stage"] = "seeding"
        self._send({"t": "accept"})
        self._commit()

    def _cmd_decline(self, cmd):
        if self.s["role"] != "joiner" or self.s["stage"] != "proposed":
            raise ProtocolError("nothing to decline")
        self.s["stage"] = "declined"
        self._send({"t": "decline"})

    def _on_accept(self, msg):
        if self.s["role"] != "inviter" or self.s["stage"] != "proposed":
            raise ProtocolError("unexpected accept")
        self.s["stage"] = "seeding"
        self._emit({"ev": "accepted"})
        self._commit()
        self._maybe_open()

    def _on_decline(self, msg):
        self.s["stage"] = "declined"
        self._emit({"ev": "declined"})

    # ------------------------------------------------------------ seed
    def _commit(self):
        nonce = secrets.token_bytes(32)
        self.s["nonce"] = nonce.hex()
        self._send({"t": "commit", "hash": commitment(nonce)})

    def _on_commit(self, msg):
        if not isinstance(msg.get("hash"), str) or len(msg["hash"]) != 64:
            raise ProtocolError("bad commitment")
        self.s["peerCommit"] = msg["hash"]
        self._maybe_open()

    def _maybe_open(self):
        if self.s.get("nonce") and self.s.get("peerCommit") and not self.s.get("opened"):
            self.s["opened"] = True
            self._send({"t": "open", "nonce": self.s["nonce"]})
            self._maybe_seed()

    def _on_open(self, msg):
        nonce = bytes.fromhex(msg["nonce"])
        if commitment(nonce) != self.s.get("peerCommit"):
            raise CheatDetected("the other player's random value doesn't match their commitment")
        self.s["peerNonce"] = nonce.hex()
        self._maybe_seed()

    def _maybe_seed(self):
        if not (self.s.get("opened") and self.s.get("peerNonce")) or self.s.get("seed") is not None:
            return
        mine, theirs = bytes.fromhex(self.s["nonce"]), bytes.fromhex(self.s["peerNonce"])
        inviter, joiner = (mine, theirs) if self.s["seat"] == 0 else (theirs, mine)
        digest = hashlib.sha256(inviter + joiner).digest()
        self.s["seed"] = int.from_bytes(digest[:4], "big")
        self.s["first"] = digest[4] & 1
        self.s["stage"] = "dealing"
        if self.s["seat"] == 0:
            if self.deck is None or not self.s.get("deck1"):
                self.deck = Deck(self.s["tiles"], 0)
                self.s["deck1"] = _hex(self.deck.setup_lock())
            self._send({"t": "deck1", "values": self.s["deck1"]})
        else:
            self.deck = Deck(self.s["tiles"], 1)

    # ------------------------------------------------------------ dealing
    def _on_deck1(self, msg):
        self._require_seat(1)
        self._send({"t": "deck2", "values": _hex(self.deck.setup_relock(_ints(msg["values"])))})

    def _on_deck2(self, msg):
        self._require_seat(0)
        self._send({"t": "deck3", "values": _hex(self.deck.setup_personalise(_ints(msg["values"])))})

    def _on_deck3(self, msg):
        self._require_seat(1)
        self._send({"t": "deck4", "values": _hex(self.deck.setup_personalise(_ints(msg["values"])))})
        self._started()

    def _on_deck4(self, msg):
        self._require_seat(0)
        self.deck.setup_finish(_ints(msg["values"]))
        self._started()

    def _started(self):
        if not self.s.get("admitted") or self.s.get("seed") is None:
            raise ProtocolError("a game can't start before the players agreed")
        self.s["stage"] = "playing"
        self.s["started"] = True   # the only proof, on disk, that this game really began
        names = [self.s["name"], self.s.get("peerName", "")]
        if self.s["seat"] == 1:
            names.reverse()
        self._emit({
            "ev": "started", "gameId": self.s["id"], "seat": self.s["seat"], "seed": self.s["seed"],
            "first": self.s["first"], "now": self.s["now"], "config": self.s["config"], "names": names,
        })

    # ------------------------------------------------------------ draws
    def _cmd_give(self, cmd):
        handles = _handle_list(cmd["handles"])
        self._send({"t": "keys", "keys": {str(h): format(self.deck.share_key(h), "x") for h in handles}})

    def _cmd_open(self, cmd):
        handles = _handle_list(cmd["handles"])
        self.s["wanted"] = sorted(set(self.s["wanted"]) | set(handles))
        self._resolve_opens()

    def _on_keys(self, msg):
        _require_dict(msg.get("keys"), "keys")
        for h, k in msg["keys"].items():
            self.s["buffer"][str(int(h))] = k
        self._resolve_opens()

    def _resolve_opens(self):
        out = {}
        still = []
        for h in self.s["wanted"]:
            if h in self.deck.known:
                out[h] = self.deck.known[h]
            elif str(h) in self.s["buffer"]:
                out[h] = self.deck.open(h, int(self.s["buffer"].pop(str(h)), 16))
            else:
                still.append(h)
        self.s["wanted"] = still
        if out:
            self._emit({"ev": "revealed", "tiles": {str(h): i for h, i in out.items()}})

    # ------------------------------------------------------------ moves
    def _cmd_move(self, cmd):
        action = cmd["action"]
        if not isinstance(action, dict):
            raise ProtocolError("bad action")
        handles = _handle_list(cmd.get("reveal", []))
        keys, claims = {}, {}
        for h in handles:
            if h not in self.deck.known:
                raise ProtocolError("can't reveal a tile I haven't seen")
            keys[str(h)] = format(self.deck.share_key(h), "x")
            claims[str(h)] = self.deck.known[h]
            self.s["claims"][str(h)] = self.deck.known[h]
        self._send({"t": "move", "action": action, "keys": keys, "claims": claims,
                    "fp": cmd.get("fp"), "index": int(cmd["index"])})

    def _on_move(self, msg):
        _require_dict(msg.get("keys"), "move keys")
        _require_dict(msg.get("claims"), "move claims")
        if not isinstance(msg.get("action"), dict):
            raise ProtocolError("bad move")
        tiles = {}
        for h, k in msg["keys"].items():
            handle = int(h)
            claimed = int(msg["claims"][h])
            tiles[str(handle)] = self.deck.check_reveal(handle, int(k, 16), claimed)
            self.s["claims"][str(handle)] = claimed
        event = {"ev": "action", "action": msg["action"], "tiles": tiles, "fp": msg.get("fp"), "index": int(msg["index"])}
        self.s["inbound"].append(event)
        if len(self.s["inbound"]) > MAX_LOG:
            raise ProtocolError("game too long")
        self._emit(event)

    def _cmd_resync(self, cmd):
        """The game restarted with `moves` moves applied: replay what it
        missed, and anything the helper still owes it."""
        moves = int(cmd["moves"])
        for event in self.s["inbound"]:
            if event["index"] >= moves:
                self._emit(event)
        if self.s["stage"] == "playing" and self.s.get("seed") is not None and moves == 0:
            self._started()

    # ------------------------------------------------------------ reshuffle
    def _cmd_reshuffle(self, cmd):
        handles = _handle_list(cmd["handles"])
        done = self.s["rebags"].get(_key(handles))
        if done is not None:
            self._emit({"ev": "rebag", "from": handles, "handles": done})
            return
        self.s["rsWanted"] = handles
        if self.s["seat"] == 0:
            if self.s.get("rsActive") != _key(handles):
                self.s["rsActive"] = _key(handles)
                self._send({"t": "rs1", "handles": handles, "values": _hex(self.deck.reshuffle_strip(handles))})
        else:
            self._maybe_rs2()

    def _on_rs1(self, msg):
        self._require_seat(1)
        self.s["rs1"] = msg
        self._maybe_rs2()

    def _maybe_rs2(self):
        msg, wanted = self.s.get("rs1"), self.s.get("rsWanted")
        if not msg or wanted is None:
            return
        if list(msg["handles"]) != wanted:
            raise ProtocolError("the two games disagree on the bag to reshuffle")
        self.s["rs1"] = None
        self._send({"t": "rs2", "values": _hex(self.deck.reshuffle_strip_shuffle(wanted, _ints(msg["values"])))})

    def _on_rs2(self, msg):
        self._require_seat(0)
        self._send({"t": "rs3", "values": _hex(self.deck.reshuffle_shuffle_personalise(_ints(msg["values"])))})

    def _on_rs3(self, msg):
        self._require_seat(1)
        values, new = self.deck.reshuffle_personalise(_ints(msg["values"]))
        self._send({"t": "rs4", "values": _hex(values)})
        self._rebagged(new)

    def _on_rs4(self, msg):
        self._require_seat(0)
        self._rebagged(self.deck.reshuffle_finish(_ints(msg["values"])))

    def _rebagged(self, new):
        old = self.s["rsWanted"]
        self.s["rebags"][_key(old)] = new
        self.s["rsWanted"] = None
        self.s["rsActive"] = None
        self._emit({"ev": "rebag", "from": old, "handles": new})

    # ------------------------------------------------------------ audit
    def _cmd_audit(self, cmd):
        self.s["inPlay"] = _handle_list(cmd["inPlay"])
        if not self.s.get("auditSent"):
            self.s["auditSent"] = True
            self._send({"t": "audit", "keys": {str(h): format(k, "x") for h, k in self.deck.audit_keys().items()}})
        self._maybe_audit()

    def _on_audit(self, msg):
        _require_dict(msg.get("keys"), "audit keys")
        if len(msg["keys"]) > 5000:
            raise ProtocolError("too many keys")
        self.s["peerKeys"] = msg["keys"]
        self._maybe_audit()

    def _maybe_audit(self):
        if self.s.get("inPlay") is None or self.s.get("peerKeys") is None:
            return
        if self.s.get("audited") is None:
            peer = {int(h): int(k, 16) for h, k in self.s["peerKeys"].items()}
            claims = {int(h): i for h, i in self.s["claims"].items()}
            result = self.deck.audit(peer, self.s["inPlay"], claims)
            self.s["audited"] = {str(h): i for h, i in result.items()}
            self.s["stage"] = "ended"
        self._emit({"ev": "audited", "tiles": self.s["audited"]})

    # ------------------------------------------------------------ misc
    def _cmd_bye(self, cmd):
        self._send({"t": "bye"})

    def _on_bye(self, msg):
        self._emit({"ev": "bye"})

    def _require_seat(self, seat):
        if self.s["seat"] != seat or self.deck is None:
            raise ProtocolError("message out of order")

    def _send(self, msg):
        self.s["outSeq"] += 1
        msg["seq"] = self.s["outSeq"]
        self.s["outLog"].append(msg)
        if len(self.s["outLog"]) > MAX_LOG:
            raise ProtocolError("game too long")
        self._save()
        if self.connected:
            self._send_raw(msg)

    def _blank(self, role, seat, name, tiles):
        return {
            "format": "omascrabble-online", "version": 1, "id": None, "role": role, "seat": seat,
            "name": clean_name(name), "peerName": "", "tiles": int(tiles), "stage": None, "config": None, "now": 0,
            "outSeq": 0, "outLog": [], "inSeq": 0, "inbound": [], "claims": {}, "wanted": [], "buffer": {},
            "rebags": {}, "rsWanted": None, "rsActive": None, "rs1": None, "deck": None,
        }

    def _adopt_id(self, game_id):
        if not all(c in "0123456789abcdef" for c in game_id) or len(game_id) != 16:
            raise ProtocolError("bad game id")
        self.s["id"] = game_id
        old = self.path
        self.path = os.path.join(os.path.dirname(self.path), game_id + ".json")
        if old != self.path:
            try:
                os.unlink(old)
            except OSError:
                pass

    def _save(self):
        if self.s is None:
            return
        if self.deck is not None:
            self.s["deck"] = self.deck.to_json()
        directory = os.path.dirname(self.path)
        os.makedirs(directory, mode=0o700, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".session-", dir=directory)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(self.s, f, separators=(",", ":"))
            os.chmod(tmp, 0o600)
            os.replace(tmp, self.path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise


def _require_dict(value, what):
    if not isinstance(value, dict) or len(value) > 5000:
        raise ProtocolError("bad %s" % what)


def _hex(values):
    return [format(v, "x") for v in values]


def _ints(values):
    if not isinstance(values, list) or len(values) > 400:
        raise ProtocolError("bad value list")
    return [int(v, 16) for v in values]


def _handle_list(values):
    if not isinstance(values, list) or len(values) > 400:
        raise ProtocolError("bad handle list")
    out = [int(h) for h in values]
    if any(h < 0 for h in out):
        raise ProtocolError("bad handle")
    return out


def _key(handles):
    return ",".join(str(h) for h in handles)
