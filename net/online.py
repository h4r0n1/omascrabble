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
            if self.tox is None:
                self.tox = tox_transport.ToxNode(os.path.join(self.dir, "tox.save"), self.name)
            self.transport = tox_transport.ToxPeer(self.tox, link, self._on_connected, self._on_message, self._on_disconnected)
        else:
            raise ValueError("no transport %r" % link["kind"])
        self.transport.start()

    def _close_transport(self):
        if self.transport is not None:
            self.transport.close()
            self.transport = None

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
                emit({"ev": "ready", "transport": self._transport_kind(), "tox": self._tox_available()})
            elif name == "invite":
                self._invite(cmd)
            elif name == "join":
                self._join(cmd)
            elif name == "resume":
                self._resume(cmd)
            elif name == "cancel":
                self._cancel()
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

    def _invite(self, cmd):
        kind = self._transport_kind()
        if kind == "none":
            emit({"ev": "error", "code": "notox", "message": "toxcore is not installed"})
            return
        self._cancel()
        tiles = TILES.get(str(cmd.get("config", {}).get("gameLanguage", "fr")), 102)
        self.session = Session(self._path("invite-" + secrets.token_hex(4)), self._send, emit)
        first = self.session.path
        game_id = self.session.new_invite(cmd.get("config") or {}, self.name, tiles)
        self.session.path = self._path(game_id)
        self.session._save()
        os.unlink(first)
        link = {"secret": secrets.token_hex(16)}
        link = TcpTransport.invite(link) if kind == "tcp" else {"kind": "tox", "role": "inviter", "secret": link["secret"]}
        self._open_transport(link)
        self._remember_link()
        emit({"ev": "invite", "link": self.transport.address(), "gameId": game_id})

    def _join(self, cmd):
        link = parse_link(cmd.get("link", ""))
        self._cancel()
        tiles = int(cmd.get("tiles", 102))
        self.session = Session(self._path("join-" + secrets.token_hex(4)), self._send, emit)
        self.session.new_join(self.name, tiles)
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
        self.session = Session.load(path, self._send, emit)
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
    Helper(args.state_dir).run()


if __name__ == "__main__":
    main()
