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
import hashlib
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
# Messages between friends outside any game (see net/online.py).
LOBBY = ("call", "call-decline", "call-cancel")

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
        "tox_self_get_public_key": (None, [c_tox, u8p]),
        "tox_self_get_connection_status": (ctypes.c_int, [c_tox]),
        "tox_self_set_name": (ctypes.c_bool, [c_tox, u8p, ctypes.c_size_t, err]),
        "tox_friend_add": (ctypes.c_uint32, [c_tox, u8p, u8p, ctypes.c_size_t, err]),
        "tox_friend_add_norequest": (ctypes.c_uint32, [c_tox, u8p, err]),
        "tox_friend_by_public_key": (ctypes.c_uint32, [c_tox, u8p, err]),
        "tox_friend_get_public_key": (ctypes.c_bool, [c_tox, ctypes.c_uint32, u8p, err]),
        "tox_friend_get_connection_status": (ctypes.c_int, [c_tox, ctypes.c_uint32, err]),
        "tox_friend_delete": (ctypes.c_bool, [c_tox, ctypes.c_uint32, err]),
        "tox_self_get_friend_list_size": (ctypes.c_size_t, [c_tox]),
        "tox_self_get_friend_list": (None, [c_tox, ctypes.POINTER(ctypes.c_uint32)]),
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


def safety_code(key_a, key_b):
    """Eight digits both machines can show: derived from the two Tox public
    keys, so a stranger using a stolen link shows a different code."""
    a, b = sorted([key_a.upper(), key_b.upper()])
    digest = hashlib.sha256(bytes.fromhex(a) + bytes.fromhex(b)).digest()
    n = int.from_bytes(digest[:6], "big") % 100000000
    return "%04d %04d" % (n // 10000, n % 10000)


def invite_accepts(link, key, now=None):
    """May the friend with this public key use this invitation? A call to a
    friend is bound to that friend; a link expires."""
    if link.get("expect") and link["expect"].upper() != key.upper():
        return False
    return (now or time.time()) <= link.get("expires", float("inf"))


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
        self.on_lobby = None        # (public key, message) for calls between friends
        self.on_presence = None     # (public key, online) when a friend comes or goes
        self._queues = {}           # friend number -> packets waiting to go out
        self._buffers = {}          # friend number -> partial incoming message
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
        # Bootstrap from the saved node list at once; refresh it meanwhile.
        try:
            with open(self._cache_path(), encoding="utf-8") as f:
                self._nodes = json.load(f)
        except (OSError, ValueError):
            self._nodes = None
        threading.Thread(target=self._fetch_nodes, daemon=True).start()

    def _cache_path(self):
        return os.path.join(os.path.dirname(self.save_path), "nodes.json")

    # identity
    def address(self):
        out = (ctypes.c_uint8 * ADDRESS_SIZE)()
        self.lib.tox_self_get_address(self.tox, out)
        return bytes(out).hex().upper()

    def public_key(self):
        out = (ctypes.c_uint8 * PUBLIC_KEY_SIZE)()
        self.lib.tox_self_get_public_key(self.tox, out)
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
        cache = self._cache_path()
        nodes = None
        try:
            with urllib.request.urlopen(NODES_URL, timeout=15) as r:
                doc = json.loads(r.read(2_000_000))
            nodes = [n for n in doc.get("nodes", []) if isinstance(n, dict) and (n.get("status_udp") or n.get("status_tcp"))]
            with open(cache, "w", encoding="utf-8") as f:
                json.dump(nodes, f)
        except (OSError, ValueError):
            if self._nodes is not None:
                return  # keep the cached list
            nodes = []
        fresh = self._nodes is None
        self._nodes = nodes
        if fresh:
            self._bootstrapped = 0

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
            try:
                key_hex = str(n["public_key"])
                if len(key_hex) != PUBLIC_KEY_SIZE * 2:
                    continue
                key = _buf(bytes.fromhex(key_hex))
                port = int(n["port"])
                if not 0 < port < 65536:
                    continue
                used += 1
                host = host.encode()
                if n.get("status_udp"):
                    self.lib.tox_bootstrap(self.tox, host, port, key, None)
                for tcp_port in (n.get("tcp_ports") or [])[:2]:
                    if isinstance(tcp_port, int) and 0 < tcp_port < 65536:
                        self.lib.tox_add_tcp_relay(self.tox, host, tcp_port, key, None)
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
        for friend in list(self._queues):
            self._flush(friend)

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
                if secrets.compare_digest(s, secret) and invite_accepts(p.link, key):
                    peer = p
            if peer is None:
                return  # not one of our invitations (or expired, or meant for someone else): ignore
            del self.invites[peer.link["secret"]]
            friend = self.lib.tox_friend_add_norequest(self.tox, _buf(bytes.fromhex(key)), None)
            if friend == 0xFFFFFFFF:
                friend = self.friend_number(key)
            self.save()
            peer.bind(key)
        except Exception:
            pass

    def _on_connection(self, tox, friend, status, user):
        try:
            self._connection(friend, status)
        except Exception:
            pass

    def _connection(self, friend, status):
        key = self.public_key_of(friend)
        up = status != CONNECTION_NONE
        if not up:
            self._queues.pop(friend, None)
            self._buffers.pop(friend, None)
        peer = self.peers.get(key)
        if peer is not None:
            peer.connection_changed(up)
        if self.on_presence is not None:
            self.on_presence(key, up)

    # ------------------------------------------------------------ messages
    # Every friend's packets are reassembled here, then routed: "auth"
    # (proof of an invitation) binds a waiting game, lobby messages (calls
    # between friends) go to the helper, anything else to the game bound to
    # that friend.
    def _on_packet(self, tox, friend, data, length, user):
        if length <= 0:
            return
        try:
            self._packet(friend, bytes(data[:min(length, MAX_PACKET)]))
        except Exception:
            pass

    def _packet(self, friend, packet):
        if packet[0] not in (MORE, LAST):
            return
        buf = self._buffers.get(friend, b"") + packet[1:]
        if len(buf) > MAX_MESSAGE:
            self._buffers.pop(friend, None)
            return
        if packet[0] == MORE:
            self._buffers[friend] = buf
            return
        self._buffers.pop(friend, None)
        try:
            msg = json.loads(buf)
        except ValueError:
            return
        if not isinstance(msg, dict):
            return
        key = self.public_key_of(friend)
        kind = msg.get("t")
        if kind == "auth":
            if key in self.peers:
                return  # already playing with this friend: a reconnection
            secret = str(msg.get("secret", ""))
            for s, p in list(self.invites.items()):
                if secrets.compare_digest(s, secret) and invite_accepts(p.link, key):
                    del self.invites[s]
                    p.bind(key)
                    return
            return
        if kind in LOBBY:
            if self.on_lobby is not None:
                self.on_lobby(key, msg)
            return
        peer = self.peers.get(key)
        if peer is not None:
            peer.on_message(msg)

    def send(self, friend, msg):
        """Queue a message for a friend; sent in packets as room allows."""
        data = json.dumps(msg, separators=(",", ":")).encode()
        chunks = [data[i:i + CHUNK] for i in range(0, len(data), CHUNK)] or [b""]
        queue = self._queues.setdefault(friend, [])
        for i, chunk in enumerate(chunks):
            queue.append(bytes([LAST if i == len(chunks) - 1 else MORE]) + chunk)
        self._flush(friend)

    def _flush(self, friend):
        queue = self._queues.get(friend)
        while queue:
            packet = queue[0]
            if not self.lib.tox_friend_send_lossless_packet(self.tox, friend, _buf(packet), len(packet), None):
                return  # toxcore's queue is full: retry on the next iteration
            queue.pop(0)

    def friend_online(self, public_key_hex):
        n = self.friend_number(public_key_hex)
        return n is not None and self.lib.tox_friend_get_connection_status(self.tox, n, None) != CONNECTION_NONE

    def send_to(self, public_key_hex, msg):
        n = self.friend_number(public_key_hex)
        if n is None or not self.friend_online(public_key_hex):
            return False
        self.send(n, msg)
        return True

    def friend_keys(self):
        count = self.lib.tox_self_get_friend_list_size(self.tox)
        numbers = (ctypes.c_uint32 * max(1, count))()
        self.lib.tox_self_get_friend_list(self.tox, numbers)
        return {self.public_key_of(numbers[i]): numbers[i] for i in range(count)}

    def prune_friends(self, keep):
        """Delete every Tox friendship not in `keep` (public keys)."""
        keep = {k.upper() for k in keep}
        removed = 0
        for key, number in self.friend_keys().items():
            if key not in keep:
                self.lib.tox_friend_delete(self.tox, number, None)
                removed += 1
        if removed:
            self.save()
        return removed

    def forget(self, public_key_hex):
        n = self.friend_number(public_key_hex)
        if n is not None:
            self.lib.tox_friend_delete(self.tox, n, None)
            self.save()


class ToxPeer:
    """The other player of one game, seen through the ToxNode."""

    kind = "tox"

    def __init__(self, node, link, on_connected, on_message, on_disconnected):
        self.node = node
        self.link = link            # {"kind","role","secret","address"?,"peer"?}
        self.on_connected = on_connected
        self.on_message = on_message
        self.on_disconnected = on_disconnected
        self.connected = False
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
        if self.friend is not None and self.node.friend_online(public_key_hex) and not self.connected:
            self.connection_changed(True)

    def address(self):
        return "omascrabble://tox/%s/%s" % (self.node.address(), self.link["secret"])

    def connection_changed(self, up):
        if up and not self.connected:
            self.connected = True
            if self.friend is None:
                self.friend = self.node.friend_number(self.link["peer"])
            if self.link["role"] == "joiner":
                # Friends from an earlier game send no friend request: prove
                # the invitation in-band, before anything else.
                self.send({"t": "auth", "secret": self.link["secret"]})
            self.on_connected()
        elif not up and self.connected:
            self.connected = False
            self.on_disconnected()

    def send(self, msg):
        if not self.connected or self.friend is None:
            return  # the session resends from its log after reconnecting
        self.node.send(self.friend, msg)

    def tick(self, now):
        pass

    def close(self):
        self.node.invites.pop(self.link.get("secret"), None)
        if self.link.get("peer") and self.node.peers.get(self.link["peer"]) is self:
            self.node.peers.pop(self.link["peer"], None)
        self.connected = False
