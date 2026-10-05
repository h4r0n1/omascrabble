"""Tox transport for the online helper: invitation links, no server of our
own, end-to-end encrypted, works across the internet.

Uses libtoxcore (the `toxcore` package) through ctypes, so nothing is
compiled. Peers find each other through the public Tox bootstrap nodes
(list fetched from nodes.tox.chat and cached); those nodes only route
encrypted packets.

  invite  the link carries this machine's Tox address and a one-time secret.
  join    the other machine sends a friend request with the secret as its
          message; the inviter accepts only a request with the right secret.
  play    messages are JSON lines cut into lossless custom packets
          (ordered, reliable) and reassembled on arrival.

The identity (tox.save) is created on first use and kept in the online state
directory, readable by the user only.
"""

import ctypes
import ctypes.util
import ipaddress
import json
import os
import random
import secrets
import tempfile
import threading
import time
import urllib.request

NODES_URL = "https://nodes.tox.chat/json"
ADDRESS_SIZE = 38
PUBLIC_KEY_SIZE = 32
MAX_PACKET = 1373
CHUNK = MAX_PACKET - 1
MORE, LAST = 160, 161
SAVEDATA_TYPE_TOX_SAVE = 1
CONNECTION_NONE = 0
MAX_MESSAGE = 4 * 1024 * 1024

_lib = None


def _load():
    global _lib
    if _lib is not None:
        return _lib
    name = ctypes.util.find_library("toxcore")
    if not name:
        raise OSError("toxcore is not installed")
    lib = ctypes.CDLL(name)
    c_tox = ctypes.c_void_p
    u8p = ctypes.POINTER(ctypes.c_uint8)
    err = ctypes.POINTER(ctypes.c_int)
    sigs = {
        "tox_options_new": (ctypes.c_void_p, [err]),
        "tox_options_free": (None, [ctypes.c_void_p]),
        "tox_options_set_udp_enabled": (None, [ctypes.c_void_p, ctypes.c_bool]),
        "tox_options_set_local_discovery_enabled": (None, [ctypes.c_void_p, ctypes.c_bool]),
        "tox_options_set_savedata_type": (None, [ctypes.c_void_p, ctypes.c_int]),
        "tox_options_set_savedata_data": (None, [ctypes.c_void_p, u8p, ctypes.c_size_t]),
        "tox_new": (c_tox, [ctypes.c_void_p, err]),
        "tox_kill": (None, [c_tox]),
        "tox_get_savedata_size": (ctypes.c_size_t, [c_tox]),
        "tox_get_savedata": (None, [c_tox, u8p]),
        "tox_bootstrap": (ctypes.c_bool, [c_tox, ctypes.c_char_p, ctypes.c_uint16, u8p, err]),
        "tox_add_tcp_relay": (ctypes.c_bool, [c_tox, ctypes.c_char_p, ctypes.c_uint16, u8p, err]),
        "tox_iteration_interval": (ctypes.c_uint32, [c_tox]),
        "tox_iterate": (None, [c_tox, ctypes.c_void_p]),
        "tox_self_get_address": (None, [c_tox, u8p]),
        "tox_self_get_connection_status": (ctypes.c_int, [c_tox]),
        "tox_self_set_name": (ctypes.c_bool, [c_tox, u8p, ctypes.c_size_t, err]),
        "tox_friend_add": (ctypes.c_uint32, [c_tox, u8p, u8p, ctypes.c_size_t, err]),
        "tox_friend_add_norequest": (ctypes.c_uint32, [c_tox, u8p, err]),
        "tox_friend_by_public_key": (ctypes.c_uint32, [c_tox, u8p, err]),
        "tox_friend_get_public_key": (ctypes.c_bool, [c_tox, ctypes.c_uint32, u8p, err]),
        "tox_friend_get_connection_status": (ctypes.c_int, [c_tox, ctypes.c_uint32, err]),
        "tox_friend_send_lossless_packet": (ctypes.c_bool, [c_tox, ctypes.c_uint32, u8p, ctypes.c_size_t, err]),
        "tox_callback_friend_request": (None, [c_tox, ctypes.c_void_p]),
        "tox_callback_friend_connection_status": (None, [c_tox, ctypes.c_void_p]),
        "tox_callback_friend_lossless_packet": (None, [c_tox, ctypes.c_void_p]),
    }
    for fname, (res, args) in sigs.items():
        fn = getattr(lib, fname)
        fn.restype = res
        fn.argtypes = args
    _lib = lib
    return lib


def available():
    try:
        _load()
        return True
    except OSError:
        return False


def _buf(data):
    return (ctypes.c_uint8 * len(data)).from_buffer_copy(data)


FRIEND_REQUEST_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint8), ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t, ctypes.c_void_p)
CONNECTION_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int, ctypes.c_void_p)
PACKET_CB = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t, ctypes.c_void_p)


class ToxNode:
    """This machine on the Tox network: one identity, many friends."""

    def __init__(self, save_path, name=""):
        self.lib = _load()
        self.save_path = save_path
        self.peers = {}             # public key hex -> ToxPeer
        self.invites = {}           # secret -> ToxPeer waiting for its friend
        self._nodes = None
        self._bootstrapped = 0
        opt_err = ctypes.c_int(0)
        options = self.lib.tox_options_new(ctypes.byref(opt_err))
        if not options:
            raise OSError("toxcore: cannot allocate options")
        try:
            self.lib.tox_options_set_udp_enabled(options, True)
            self.lib.tox_options_set_local_discovery_enabled(options, True)
            saved = None
            if os.path.exists(save_path):
                with open(save_path, "rb") as f:
                    saved = f.read()
                self.lib.tox_options_set_savedata_type(options, SAVEDATA_TYPE_TOX_SAVE)
                self._saved = _buf(saved)
                self.lib.tox_options_set_savedata_data(options, self._saved, len(saved))
            new_err = ctypes.c_int(0)
            self.tox = self.lib.tox_new(options, ctypes.byref(new_err))
        finally:
            self.lib.tox_options_free(options)
        if not self.tox:
            raise OSError("toxcore: cannot start (error %d)" % new_err.value)
        if name:
            data = name.encode()[:128]
            self.lib.tox_self_set_name(self.tox, _buf(data), len(data), None)
        self._cbs = [
            FRIEND_REQUEST_CB(self._on_request),
            CONNECTION_CB(self._on_connection),
            PACKET_CB(self._on_packet),
        ]
        self.lib.tox_callback_friend_request(self.tox, ctypes.cast(self._cbs[0], ctypes.c_void_p))
        self.lib.tox_callback_friend_connection_status(self.tox, ctypes.cast(self._cbs[1], ctypes.c_void_p))
        self.lib.tox_callback_friend_lossless_packet(self.tox, ctypes.cast(self._cbs[2], ctypes.c_void_p))
        self.save()
        threading.Thread(target=self._fetch_nodes, daemon=True).start()

    # identity
    def address(self):
        out = (ctypes.c_uint8 * ADDRESS_SIZE)()
        self.lib.tox_self_get_address(self.tox, out)
        return bytes(out).hex().upper()

    def save(self):
        size = self.lib.tox_get_savedata_size(self.tox)
        out = (ctypes.c_uint8 * size)()
        self.lib.tox_get_savedata(self.tox, out)
        directory = os.path.dirname(self.save_path)
        fd, tmp = tempfile.mkstemp(prefix=".tox-", dir=directory)
        with os.fdopen(fd, "wb") as f:
            f.write(bytes(out))
        os.chmod(tmp, 0o600)
        os.replace(tmp, self.save_path)

    # network
    def _fetch_nodes(self):
        cache = os.path.join(os.path.dirname(self.save_path), "nodes.json")
        nodes = None
        try:
            with urllib.request.urlopen(NODES_URL, timeout=15) as r:
                doc = json.loads(r.read(2_000_000))
            nodes = [n for n in doc.get("nodes", []) if isinstance(n, dict) and (n.get("status_udp") or n.get("status_tcp"))]
            with open(cache, "w", encoding="utf-8") as f:
                json.dump(nodes, f)
        except (OSError, ValueError):
            try:
                with open(cache, encoding="utf-8") as f:
                    nodes = json.load(f)
            except (OSError, ValueError):
                nodes = []
        self._nodes = nodes

    def _bootstrap(self):
        nodes = list(self._nodes or [])
        random.shuffle(nodes)
        used = 0
        for n in nodes:
            if used >= 8:
                break
            # Only literal addresses: a name (or the list's "-" placeholder)
            # would make toxcore resolve it, blocking the helper.
            host = None
            for field in ("ipv4", "ipv6"):
                try:
                    host = str(ipaddress.ip_address(str(n.get(field, "")).strip("[]")))
                    break
                except ValueError:
                    continue
            if host is None:
                continue
            used += 1
            try:
                key = _buf(bytes.fromhex(n["public_key"]))
                host = host.encode()
                if n.get("status_udp"):
                    self.lib.tox_bootstrap(self.tox, host, int(n["port"]), key, None)
                for port in (n.get("tcp_ports") or [])[:2]:
                    self.lib.tox_add_tcp_relay(self.tox, host, int(port), key, None)
            except (KeyError, TypeError, ValueError):
                continue
        self._bootstrapped = time.time()

    def online(self):
        return self.lib.tox_self_get_connection_status(self.tox) != CONNECTION_NONE

    def interval(self):
        return max(0.01, self.lib.tox_iteration_interval(self.tox) / 1000.0)

    def iterate(self):
        if self._nodes is not None and (not self._bootstrapped or (not self.online() and time.time() - self._bootstrapped > 20)):
            self._bootstrap()
        self.lib.tox_iterate(self.tox, None)
        for peer in list(self.peers.values()):
            peer.flush()

    def close(self):
        if self.tox:
            self.save()
            self.lib.tox_kill(self.tox)
            self.tox = None

    # friends
    def friend_number(self, public_key_hex):
        n = self.lib.tox_friend_by_public_key(self.tox, _buf(bytes.fromhex(public_key_hex)), None)
        return None if n == 0xFFFFFFFF else n

    def add_friend(self, address_hex, message):
        data = message.encode()
        e = ctypes.c_int(0)
        n = self.lib.tox_friend_add(self.tox, _buf(bytes.fromhex(address_hex)), _buf(data), len(data), ctypes.byref(e))
        if n == 0xFFFFFFFF:
            # Already a friend (an earlier game): reuse.
            existing = self.friend_number(address_hex[:PUBLIC_KEY_SIZE * 2])
            if existing is None:
                raise OSError("toxcore: friend request failed (error %d)" % e.value)
            return existing
        self.save()
        return n

    def public_key_of(self, friend):
        out = (ctypes.c_uint8 * PUBLIC_KEY_SIZE)()
        self.lib.tox_friend_get_public_key(self.tox, friend, out, None)
        return bytes(out).hex().upper()

    def _on_request(self, tox, pk, msg, length, user):
        try:
            key = bytes(pk[:PUBLIC_KEY_SIZE]).hex().upper()
            text = bytes(msg[:min(length, 256)]).decode("utf-8", "replace")
            secret = text.split(" ", 1)[0]
            peer = None
            for s, p in self.invites.items():
                if secrets.compare_digest(s, secret):
                    peer = p
            if peer is None:
                return  # not one of our invitations: ignore
            del self.invites[peer.link["secret"]]
            friend = self.lib.tox_friend_add_norequest(self.tox, _buf(bytes.fromhex(key)), None)
            if friend == 0xFFFFFFFF:
                friend = self.friend_number(key)
            self.save()
            peer.bind(key)
        except Exception:
            pass

    def _on_connection(self, tox, friend, status, user):
        key = self.public_key_of(friend)
        peer = self.peers.get(key)
        if peer is not None:
            peer.connection_changed(status != CONNECTION_NONE)

    def _on_packet(self, tox, friend, data, length, user):
        key = self.public_key_of(friend)
        peer = self.peers.get(key)
        if peer is not None and length > 0:
            peer.packet(bytes(data[:length]))


class ToxPeer:
    """The other player of one session, seen through the ToxNode."""

    kind = "tox"

    def __init__(self, node, link, on_connected, on_message, on_disconnected):
        self.node = node
        self.link = link            # {"kind","role","secret","address"?,"peer"?}
        self.on_connected = on_connected
        self.on_message = on_message
        self.on_disconnected = on_disconnected
        self.connected = False
        self.incoming = b""
        self.queue = []             # packets waiting for room in toxcore's queue
        self.friend = None

    def start(self):
        if self.link["role"] == "inviter" and not self.link.get("peer"):
            self.node.invites[self.link["secret"]] = self
        elif self.link["role"] == "joiner" and not self.link.get("peer"):
            address = self.link["address"]
            self.friend = self.node.add_friend(address, "%s omascrabble" % self.link["secret"])
            self.bind(address[:PUBLIC_KEY_SIZE * 2])
        else:
            self.bind(self.link["peer"])

    def bind(self, public_key_hex):
        self.link["peer"] = public_key_hex
        self.node.peers[public_key_hex] = self
        self.friend = self.node.friend_number(public_key_hex)
        if self.friend is not None:
            status = self.node.lib.tox_friend_get_connection_status(self.node.tox, self.friend, None)
            if status != CONNECTION_NONE and not self.connected:
                self.connection_changed(True)

    def address(self):
        return "omascrabble://tox/%s/%s" % (self.node.address(), self.link["secret"])

    def connection_changed(self, up):
        if up and not self.connected:
            self.connected = True
            self.incoming = b""
            self.on_connected()
        elif not up and self.connected:
            self.connected = False
            self.queue = []
            self.on_disconnected()

    def packet(self, data):
        marker, body = data[0], data[1:]
        if marker not in (MORE, LAST):
            return
        self.incoming += body
        if len(self.incoming) > MAX_MESSAGE:
            self.incoming = b""
            return
        if marker == LAST:
            text, self.incoming = self.incoming, b""
            try:
                msg = json.loads(text)
            except ValueError:
                return
            self.on_message(msg)

    def send(self, msg):
        if not self.connected or self.friend is None:
            return  # the session resends from its log after reconnecting
        data = json.dumps(msg, separators=(",", ":")).encode()
        chunks = [data[i:i + CHUNK] for i in range(0, len(data), CHUNK)] or [b""]
        for i, chunk in enumerate(chunks):
            marker = LAST if i == len(chunks) - 1 else MORE
            self.queue.append(bytes([marker]) + chunk)
        self.flush()

    def flush(self):
        while self.queue and self.connected and self.friend is not None:
            packet = self.queue[0]
            ok = self.node.lib.tox_friend_send_lossless_packet(self.node.tox, self.friend, _buf(packet), len(packet), None)
            if not ok:
                return  # toxcore's send queue is full: retry on the next iteration
            self.queue.pop(0)

    def tick(self, now):
        pass

    def close(self):
        self.node.invites.pop(self.link.get("secret"), None)
        if self.link.get("peer"):
            self.node.peers.pop(self.link["peer"], None)
        self.connected = False
