#!/usr/bin/env python3
"""Omascrabble online helper: the bridge between the game and the other
machine, for two-player games with no referee (docs/ONLINE.md).

The game starts it and talks to it in JSON lines: commands on stdin, events
on stdout. It holds one session (net/session.py) at a time and carries it
over a transport:

  tox  (default) through libtoxcore: invitation links, no server, encrypted,
       works across the internet. Needs the toxcore package.
  tcp  a direct connection, for tests and local networks
       (OMASCRABBLE_TRANSPORT=tcp; OMASCRABBLE_TCP_HOST / _PORT to listen).

Python standard library only. Sessions live in
$XDG_STATE_HOME/omascrabble/online (readable by the user only).
"""

import sys

# Never write __pycache__ next to these files: they live in the plugin's
# folder, and Omarchy reloads a plugin (closing the game) whenever anything
# in that folder changes.
sys.dont_write_bytecode = True

import argparse  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import secrets  # noqa: E402
import selectors  # noqa: E402
import socket  # noqa: E402
import time  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from session import Session  # noqa: E402

MAX_LINE = 2 * 1024 * 1024
TILES = {"fr": 102, "en": 100}


def emit(event):
    sys.stdout.write(json.dumps(event, separators=(",", ":")) + "\n")
    sys.stdout.flush()


class LineBuffer:
    def __init__(self):
        self.data = b""

    def feed(self, chunk):
        self.data += chunk
        if len(self.data) > MAX_LINE and b"\n" not in self.data:
            raise ValueError("line too long")
        lines = self.data.split(b"\n")
        self.data = lines.pop()
        return [line for line in lines if line.strip()]


# ------------------------------------------------------------------ TCP

class TcpTransport:
    """One peer over a plain TCP connection, JSON lines. The joiner proves it
    holds the invitation by sending its secret first."""

    kind = "tcp"

    def __init__(self, sel, link, on_connected, on_message, on_disconnected):
        self.sel = sel
        self.link = link            # {"kind","role","host","port","secret"}
        self.on_connected = on_connected
        self.on_message = on_message
        self.on_disconnected = on_disconnected
        self.server = None
        self.conn = None
        self.buffer = None
        self.authed = False
        self.next_try = 0

    @staticmethod
    def invite(link_info):
        host = os.environ.get("OMASCRABBLE_TCP_HOST", "127.0.0.1")
        port = int(os.environ.get("OMASCRABBLE_TCP_PORT", "0"))
        link_info.update({"kind": "tcp", "role": "inviter", "host": host, "port": port})
        return link_info

    def start(self):
        if self.link["role"] == "inviter":
            self.server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server.bind((self.link["host"], int(self.link["port"])))
            self.server.listen(1)
            self.server.setblocking(False)
            self.link["port"] = self.server.getsockname()[1]
            self.sel.register(self.server, selectors.EVENT_READ, self._accept)

    def address(self):
        return "omascrabble://tcp/%s:%d/%s" % (self.link["host"], self.link["port"], self.link["secret"])

    def tick(self, now):
        if self.link["role"] == "joiner" and self.conn is None and now >= self.next_try:
            self.next_try = now + 2
            try:
                conn = socket.create_connection((self.link["host"], int(self.link["port"])), timeout=3)
            except OSError:
                return
            self._adopt(conn)
            self._write({"t": "auth", "secret": self.link["secret"]})
            self.authed = True
            self.on_connected()

    def _accept(self, sock):
        conn, _ = sock.accept()
        if self.conn is not None:
            conn.close()  # one peer at a time
            return
        self._adopt(conn)
        self.authed = False

    def _adopt(self, conn):
        conn.setblocking(False)
        self.conn = conn
        self.buffer = LineBuffer()
        self.sel.register(conn, selectors.EVENT_READ, self._read)

    def _read(self, conn):
        try:
            chunk = conn.recv(65536)
        except (BlockingIOError, InterruptedError):
            return
        except OSError:
            chunk = b""
        if not chunk:
            self._drop()
            return
        try:
            lines = self.buffer.feed(chunk)
        except ValueError:
            self._drop()
            return
        for line in lines:
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if not self.authed:
                if isinstance(msg, dict) and msg.get("t") == "auth" and secrets.compare_digest(str(msg.get("secret", "")), self.link["secret"]):
                    self.authed = True
                    self.on_connected()
                else:
                    self._drop()
                    return
                continue
            self.on_message(msg)

    def _drop(self):
        if self.conn is not None:
            try:
                self.sel.unregister(self.conn)
            except (KeyError, ValueError):
                pass
            self.conn.close()
            self.conn = None
            if self.authed:
                self.authed = False
                self.on_disconnected()

    def send(self, msg):
        if self.conn is not None and self.authed:
            self._write(msg)

    def _write(self, msg):
        data = (json.dumps(msg, separators=(",", ":")) + "\n").encode()
        try:
            self.conn.setblocking(True)
            self.conn.sendall(data)
            self.conn.setblocking(False)
        except OSError:
            self._drop()

    def close(self):
        self._drop()
        if self.server is not None:
            self.sel.unregister(self.server)
            self.server.close()
            self.server = None


def parse_link(text):
    """omascrabble://tcp/host:port/secret or omascrabble://tox/address/secret"""
    text = str(text).strip()
    prefix = "omascrabble://"
    if not text.startswith(prefix):
        raise ValueError("not an Omascrabble invitation")
    parts = text[len(prefix):].split("/")
    if len(parts) != 3:
        raise ValueError("not an Omascrabble invitation")
    kind, where, secret = parts
    if not secret or not all(c in "0123456789abcdef" for c in secret) or len(secret) > 64:
        raise ValueError("not an Omascrabble invitation")
    if kind == "tcp":
        host, _, port = where.rpartition(":")
        return {"kind": "tcp", "role": "joiner", "host": host, "port": int(port), "secret": secret}
    if kind == "tox":
        if len(where) != 76 or not all(c in "0123456789ABCDEFabcdef" for c in where):
            raise ValueError("not an Omascrabble invitation")
        return {"kind": "tox", "role": "joiner", "address": where.upper(), "secret": secret}
    raise ValueError("not an Omascrabble invitation")


# ------------------------------------------------------------------ helper

class Helper:
    def __init__(self, state_dir):
        self.dir = os.path.join(state_dir, "omascrabble", "online")
        os.makedirs(self.dir, mode=0o700, exist_ok=True)
        os.chmod(self.dir, 0o700)
        self.sel = selectors.DefaultSelector()
        self.session = None
        self.transport = None
        self.tox = None
        self.name = ""
        self.running = True
        self.friends = self._load_friends()   # Tox public key -> {"name", "last"}
        self.calling = None       # our call to a friend: {"friend", "secret", "config", "sent"}
        self.incoming = {}        # friend -> their call to us

    # transport plumbing
    def _send(self, msg):
        if self.transport is not None:
            self.transport.send(msg)

    def _on_connected(self):
        if self.session is not None:
            self.session.on_connected()

    def _on_message(self, msg):
        if self.session is not None:
            self.session.on_message(msg)
            self._remember_link()

    def _on_disconnected(self):
        if self.session is not None:
            self.session.on_disconnected()

    def _transport_kind(self):
        wanted = os.environ.get("OMASCRABBLE_TRANSPORT", "")
        if wanted:
            return wanted
        return "tox" if self._tox_available() else "none"

    def _tox_available(self):
        try:
            import tox_transport
            return tox_transport.available()
        except Exception:
            return False

    def _open_transport(self, link):
        self._close_transport()
        if link["kind"] == "tcp":
            self.transport = TcpTransport(self.sel, link, self._on_connected, self._on_message, self._on_disconnected)
        elif link["kind"] == "tox":
            import tox_transport
            self.transport = tox_transport.ToxPeer(self._ensure_tox(), link, self._on_connected, self._on_message, self._on_disconnected)
        else:
            raise ValueError("no transport %r" % link["kind"])
        self.transport.start()

    def _close_transport(self):
        if self.transport is not None:
            self.transport.close()
            self.transport = None

    # ------------------------------------------------------------ friends
    def _friends_path(self):
        return os.path.join(self.dir, "friends.json")

    def _load_friends(self):
        try:
            with open(self._friends_path(), encoding="utf-8") as f:
                data = json.load(f)
            return {k: v for k, v in data.items() if isinstance(v, dict) and len(k) == 64}
        except FileNotFoundError:
            return self._friends_from_games()
        except (OSError, ValueError, AttributeError):
            return {}

    def _friends_from_games(self):
        """First run with friends: the people of earlier online games (over
        Tox) become friends. Only done while there is no friends file, so a
        friend removed later stays removed."""
        friends = {}
        for name in os.listdir(self.dir):
            if not name.endswith(".json") or name in ("friends.json", "nodes.json"):
                continue
            try:
                with open(os.path.join(self.dir, name), encoding="utf-8") as f:
                    s = json.load(f)
            except (OSError, ValueError):
                continue
            link = s.get("link") if isinstance(s, dict) else None
            key = link.get("peer") if isinstance(link, dict) and link.get("kind") == "tox" else None
            if not key or len(key) != 64 or s.get("stage") not in ("playing", "ended", "dealing"):
                continue
            last = int(os.path.getmtime(os.path.join(self.dir, name)))
            if key not in friends or friends[key]["last"] < last:
                friends[key] = {"name": str(s.get("peerName", ""))[:40], "last": last}
        if friends:
            self.friends = friends
            self._save_friends()
        return friends

    def _save_friends(self):
        tmp = self._friends_path() + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.friends, f)
        os.chmod(tmp, 0o600)
        os.replace(tmp, self._friends_path())

    def _friends_event(self):
        out = []
        for key, f in sorted(self.friends.items(), key=lambda kv: -kv[1].get("last", 0)):
            online = bool(self.tox and self.tox.friend_online(key))
            out.append({"id": key, "name": f.get("name", ""), "online": online, "last": f.get("last", 0)})
        emit({"ev": "friends", "list": out})

    def _session_event(self, ev):
        # Anyone we really play with over Tox becomes a friend we can call.
        if ev.get("ev") in ("peer", "started") and self.transport is not None and self.transport.kind == "tox":
            key = self.transport.link.get("peer")
            name = self.session.s.get("peerName", "") if self.session else ""
            if key and len(key) == 64:
                entry = self.friends.get(key, {})
                entry["name"] = name or entry.get("name", "")
                entry["last"] = int(time.time())
                self.friends[key] = entry
                self._save_friends()
                self._friends_event()
            if ev.get("ev") == "started":
                self.calling = None
        emit(ev)

    def _ensure_tox(self):
        if self.tox is None:
            import tox_transport
            self.tox = tox_transport.ToxNode(os.path.join(self.dir, "tox.save"), self.name)
            self.tox.on_lobby = self._lobby
            self.tox.on_presence = self._presence
        return self.tox

    def _presence(self, key, up):
        if key in self.friends:
            self._friends_event()
        if up and self.calling and self.calling["friend"] == key and not self.calling["sent"]:
            self._send_call()

    def _send_call(self):
        c = self.calling
        if self.tox.send_to(c["friend"], {"t": "call", "secret": c["secret"], "config": c["config"], "name": self.name}):
            c["sent"] = True
        emit({"ev": "calling", "friend": c["friend"], "online": c["sent"]})

    def _lobby(self, key, msg):
        if key not in self.friends:
            return  # only people we've played with may call
        kind = msg.get("t")
        secret = str(msg.get("secret", ""))
        if not secret or len(secret) > 64 or not all(ch in "0123456789abcdef" for ch in secret):
            return
        if kind == "call" and isinstance(msg.get("config"), dict):
            self.incoming[key] = {"secret": secret, "config": msg["config"]}
            emit({"ev": "call", "friend": key, "name": self.friends[key].get("name") or str(msg.get("name", ""))[:40],
                  "config": msg["config"]})
        elif kind == "call-cancel":
            if self.incoming.get(key, {}).get("secret") == secret:
                del self.incoming[key]
                emit({"ev": "call-cancelled", "friend": key})
        elif kind == "call-decline":
            if self.calling and self.calling["friend"] == key and self.calling["secret"] == secret:
                self.calling = None
                self._cancel()
                emit({"ev": "declined", "friend": key})

    def _call(self, cmd):
        key = str(cmd.get("friend", ""))
        if key not in self.friends:
            raise ValueError("unknown friend")
        if self._transport_kind() != "tox":
            raise ValueError("calling a friend needs toxcore")
        self._ensure_tox()
        self._invite({"config": cmd.get("config") or {}}, announce=False)
        self.calling = {"friend": key, "secret": self.transport.link["secret"], "config": cmd.get("config") or {}, "sent": False}
        self._send_call()

    def _answer(self, cmd):
        key = str(cmd.get("friend", ""))
        call = self.incoming.pop(key, None)
        if call is None:
            raise ValueError("no invitation from this friend")
        if not cmd.get("accept"):
            if self.tox is not None:
                self.tox.send_to(key, {"t": "call-decline", "secret": call["secret"]})
            return
        tiles = TILES.get(str(call["config"].get("gameLanguage", "fr")), 102)
        self._start_join({"kind": "tox", "role": "joiner", "peer": key, "secret": call["secret"]}, tiles, auto_accept=True)

    def _forget(self, cmd):
        key = str(cmd.get("friend", ""))
        if self.friends.pop(key, None) is not None:
            self._save_friends()
            if self.tox is not None and key not in self.tox.peers:
                self.tox.forget(key)
        self._friends_event()

    def _remember_link(self):
        if self.session is not None and self.transport is not None:
            self.session.s["link"] = self.transport.link
            self.session._save()

    def _path(self, name):
        return os.path.join(self.dir, name + ".json")

    # commands
    def handle(self, cmd):
        name = cmd.get("cmd")
        try:
            if name == "hello":
                self.name = str(cmd.get("name", ""))[:40]
                kind = self._transport_kind()
                emit({"ev": "ready", "transport": kind, "tox": self._tox_available()})
                # Join the Tox network now, while the player is still on the
                # online screen: by the time they invite or paste a link, the
                # node is already reachable (and friends can call).
                if kind == "tox":
                    self._ensure_tox()
                self._friends_event()
            elif name == "invite":
                self._invite(cmd)
            elif name == "join":
                self._join(cmd)
            elif name == "resume":
                self._resume(cmd)
            elif name == "cancel":
                if self.calling and self.tox is not None:
                    self.tox.send_to(self.calling["friend"], {"t": "call-cancel", "secret": self.calling["secret"]})
                self.calling = None
                self._cancel()
            elif name == "friends":
                self._friends_event()
            elif name == "call":
                self._call(cmd)
            elif name == "answer":
                self._answer(cmd)
            elif name == "forget":
                self._forget(cmd)
            elif name == "quit":
                self.running = False
            elif self.session is not None:
                self.session.command(cmd)
            else:
                emit({"ev": "error", "code": "no-session", "message": "no online game"})
        except ValueError as e:
            emit({"ev": "error", "code": "link", "message": str(e)})
        except OSError as e:
            emit({"ev": "error", "code": "network", "message": str(e)})

    def _invite(self, cmd, announce=True):
        kind = self._transport_kind()
        if kind == "none":
            emit({"ev": "error", "code": "notox", "message": "toxcore is not installed"})
            return
        self._cancel()
        tiles = TILES.get(str(cmd.get("config", {}).get("gameLanguage", "fr")), 102)
        self.session = Session(self._path("invite-" + secrets.token_hex(4)), self._send, self._session_event)
        first = self.session.path
        game_id = self.session.new_invite(cmd.get("config") or {}, self.name, tiles)
        self.session.path = self._path(game_id)
        self.session._save()
        os.unlink(first)
        link = {"secret": secrets.token_hex(16)}
        link = TcpTransport.invite(link) if kind == "tcp" else {"kind": "tox", "role": "inviter", "secret": link["secret"]}
        self._open_transport(link)
        self._remember_link()
        if announce:
            emit({"ev": "invite", "link": self.transport.address(), "gameId": game_id})
        self.session.precompute()

    def _join(self, cmd):
        self._start_join(parse_link(cmd.get("link", "")), int(cmd.get("tiles", 102)))

    def _start_join(self, link, tiles, auto_accept=False):
        self._cancel()
        self.session = Session(self._path("join-" + secrets.token_hex(4)), self._send, self._session_event)
        self.session.new_join(self.name, tiles, auto_accept)
        self._open_transport(link)
        self._remember_link()
        emit({"ev": "joining"})

    def _resume(self, cmd):
        game_id = str(cmd.get("gameId", ""))
        if not game_id or not all(c in "0123456789abcdef" for c in game_id):
            raise ValueError("bad game id")
        path = self._path(game_id)
        if not os.path.exists(path):
            emit({"ev": "error", "code": "no-session", "message": "this online game can't be resumed on this machine"})
            return
        if self.session is not None and self.session.game_id == game_id:
            self.session.command({"cmd": "resync", "moves": int(cmd.get("moves", 0))})
            return
        self._cancel(keep=True)
        self.session = Session.load(path, self._send, self._session_event)
        link = self.session.s.get("link")
        if not link:
            emit({"ev": "error", "code": "no-session", "message": "no connection details for this game"})
            return
        self._open_transport(link)
        emit({"ev": "resumed", "gameId": game_id})
        self.session.command({"cmd": "resync", "moves": int(cmd.get("moves", 0))})

    def _cancel(self, keep=False):
        self._close_transport()
        if self.session is not None and not keep and self.session.stage in ("inviting", "joining", "proposed", "declined"):
            try:
                os.unlink(self.session.path)
            except OSError:
                pass
        self.session = None

    # loop
    def run(self):
        stdin = sys.stdin.buffer.raw if hasattr(sys.stdin.buffer, "raw") else sys.stdin.buffer
        os.set_blocking(stdin.fileno(), False)
        lines = LineBuffer()

        def read_stdin(f):
            try:
                chunk = os.read(f.fileno(), 65536)
            except BlockingIOError:
                return
            if not chunk:
                self.running = False
                return
            for line in lines.feed(chunk):
                try:
                    cmd = json.loads(line)
                except ValueError:
                    emit({"ev": "error", "code": "command", "message": "unreadable command"})
                    continue
                if isinstance(cmd, dict):
                    self.handle(cmd)

        self.sel.register(stdin, selectors.EVENT_READ, read_stdin)
        while self.running:
            timeout = 0.25
            if self.tox is not None:
                timeout = min(timeout, self.tox.interval())
            for key, _ in self.sel.select(timeout):
                key.data(key.fileobj)
            now = time.time()
            if self.tox is not None:
                self.tox.iterate()
            if self.transport is not None:
                self.transport.tick(now)
        self._close_transport()
        if self.tox is not None:
            self.tox.close()


def main():
    parser = argparse.ArgumentParser(description="Omascrabble online helper (spoken to by the game).")
    data = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    parser.add_argument("--state-dir", default=data)
    args = parser.parse_args()
    start_pool()
    Helper(args.state_dir).run()


def start_pool():
    """Worker processes for the bag's big-number maths, forked now — before
    any thread or network handle exists — so they share nothing but the
    already-imported code (and write nothing anywhere)."""
    import multiprocessing
    import deck
    workers = min(6, os.cpu_count() or 1)
    if workers < 2:
        return
    try:
        pool = multiprocessing.get_context("fork").Pool(workers)
    except (OSError, ValueError):
        return
    chunk = lambda n: max(1, n // (workers * 2))
    deck.POWMAP = lambda pairs: pool.starmap(deck.pow_mod, pairs, chunksize=chunk(len(pairs)))


if __name__ == "__main__":
    main()
