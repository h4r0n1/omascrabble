#!/usr/bin/env python3
"""Builds an optional definitions pack for Omascrabble.

    python3 tools/install-definitions.py               # French (Wiktionnaire)
    python3 tools/install-definitions.py --lang en     # English (Wiktionary)
    python3 tools/install-definitions.py --source extract.jsonl[.gz]
    python3 tools/install-definitions.py --progress-json   # for the game's UI

The game runs this script itself when you click "Download" (with
--progress-json: one JSON object per line on stdout, see emit()); it can also
be run by hand.

The definitions come from Wiktionary — the French Wiktionnaire for French
games, the English Wiktionary for English games — as extracted by Kaikki.org
(wiktextract), under CC BY-SA 4.0. The game never downloads anything: this
script does it once, on request, then writes small JSON shards to
$XDG_DATA_HOME/omascrabble/definitions/<lang> (default ~/.local/share/...),
which the game reads offline.

Only entries of that language whose spelling is playable in the game's own
word list are kept (read from the plugin's dictionary/data/open-<lang>.dawg,
so the pack always matches the game), with at most three short definitions
each. The download (French ~740 MB, English ~520 MB compressed) is streamed
and filtered on the fly; nothing large is written to disk. Python 3 standard
library only.
"""

import argparse
import base64
import gzip
import io
import json
import os
import re
import shutil
import signal
import socket
import sys
import tempfile
import time
import urllib.request

LANGUAGES = {
    "fr": {
        "source": "https://kaikki.org/frwiktionary/raw-wiktextract-data.jsonl.gz",
        "name": "Wiktionnaire (fr.wiktionary.org), extracted by Kaikki.org / wiktextract",
    },
    "en": {
        "source": "https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl.gz",
        "name": "Wiktionary (en.wiktionary.org), extracted by Kaikki.org / wiktextract",
    },
}
# English extracts give a bare part of speech; French ones a title ("Nom commun").
POS_NAMES = {
    "noun": "noun", "verb": "verb", "adj": "adjective", "adv": "adverb", "prep": "preposition",
    "conj": "conjunction", "pron": "pronoun", "intj": "interjection", "det": "determiner",
    "num": "numeral", "particle": "particle", "article": "article", "abbrev": "abbreviation",
    "contraction": "contraction", "prefix": "prefix", "suffix": "suffix", "phrase": "phrase",
}
SKIPPED_POS = {"name", "character", "symbol", "letter"}
PACK_FORMAT = "omascrabble-definitions"
PACK_VERSION = 1
MAX_SENSES = 3
MAX_GLOSS = 240
HERE = os.path.dirname(os.path.abspath(__file__))
JSON_PROGRESS = False


def emit(event, **fields):
    """Progress for the game's UI: {"event": start|progress|writing|done|error, ...}."""
    if JSON_PROGRESS:
        fields["event"] = event
        print(json.dumps(fields), flush=True)


class InstallError(Exception):
    """A failure the UI can explain: code is network | source | disk."""

    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
PLUGIN = os.path.dirname(HERE)

# Same folding as dictionary/normalize.mjs: diacritics and ligatures fold to
# tile letters; any other character makes the spelling unplayable.
FOLDS = {
    "à": "A", "â": "A", "ä": "A", "é": "E", "è": "E", "ê": "E", "ë": "E",
    "î": "I", "ï": "I", "ô": "O", "ö": "O", "ù": "U", "û": "U", "ü": "U",
    "ÿ": "Y", "ç": "C", "œ": "OE", "æ": "AE", "á": "A", "í": "I", "ó": "O", "ú": "U",
    "ñ": "N", "å": "A", "ø": "O",
}


def fold(word):
    out = []
    for ch in word:
        o = ord(ch)
        if 65 <= o <= 90:
            out.append(ch)
        elif 97 <= o <= 122:
            out.append(ch.upper())
        elif ch.lower() in FOLDS:
            out.append(FOLDS[ch.lower()])
        else:
            return None
    return "".join(out)


def read_lexicon(path):
    """Every word of a game DAWG file (see dictionary/dawg.mjs for the format)."""
    with open(path, encoding="utf-8") as f:
        header = json.loads(f.readline())
        raw = base64.b64decode(f.read().strip())
    n = header["edges"]
    edges = [int.from_bytes(raw[i * 4:i * 4 + 4], "little") for i in range(n)]
    lb, tb = header["letterBits"], header["tierBits"]
    letter_mask, terminal, last = (1 << lb) - 1, 1 << lb, 1 << (lb + 1)
    child_shift = lb + 2 + tb
    alphabet = header["alphabet"]
    words = set()
    stack = [(header["root"], "")]
    while stack:
        node, prefix = stack.pop()
        i = node
        while True:
            e = edges[i]
            w = prefix + alphabet[e & letter_mask]
            if e & terminal:
                words.add(w)
            child = e >> child_shift
            if child:
                stack.append((child, w))
            if e & last:
                break
            i += 1
    if len(words) != header["words"]:
        raise SystemExit("dictionary word count mismatch: %d != %d" % (len(words), header["words"]))
    return words


def clean_gloss(text):
    text = re.sub(r"\s+", " ", str(text)).strip()
    if len(text) > MAX_GLOSS:
        text = text[:MAX_GLOSS - 1].rsplit(" ", 1)[0] + "…"
    return text


def entry_from(record):
    if record.get("pos") in SKIPPED_POS:
        return None
    senses = []
    lemma = None
    for sense in record.get("senses") or []:
        glosses = sense.get("glosses") or []
        if not glosses:
            continue
        senses.append(clean_gloss(glosses[-1]))
        for f in sense.get("form_of") or []:
            if isinstance(f, dict) and f.get("word") and not lemma:
                lemma = str(f["word"])
        if len(senses) >= MAX_SENSES:
            break
    if not senses:
        return None
    if lemma:
        senses = senses[:1]  # "plural of house" — the base word carries the meaning
    pos = record.get("pos_title") or POS_NAMES.get(record.get("pos"), record.get("pos")) or ""
    entry = {"w": record["word"], "p": str(pos), "d": senses}
    if lemma and lemma != record["word"]:
        entry["of"] = lemma
    return entry


def open_source(source):
    if re.match(r"^https?://", source):
        print("Downloading", source, file=sys.stderr)
        try:
            stream = urllib.request.urlopen(source, timeout=60)
        except (OSError, ValueError) as e:
            raise InstallError("network", str(e))
        total = int(stream.headers.get("Content-Length") or 0)
    else:
        stream = open(source, "rb")
        total = os.path.getsize(source)
    counter = CountingReader(stream, total)
    if source.endswith(".gz"):
        return counter, io.TextIOWrapper(gzip.GzipFile(fileobj=counter), encoding="utf-8")
    return counter, io.TextIOWrapper(counter, encoding="utf-8")


class CountingReader(io.RawIOBase):
    def __init__(self, inner, total):
        self.inner, self.total, self.done = inner, total, 0

    def readable(self):
        return True

    def readinto(self, b):
        try:
            data = self.inner.read(len(b))
        except (socket.timeout, ConnectionError) as e:
            raise InstallError("network", str(e))
        n = len(data)
        b[:n] = data
        self.done += n
        return n


def build(lang, source, lexicon, out_dir):
    words = read_lexicon(lexicon)
    print("Playable words:", len(words), file=sys.stderr)
    marks = ('"lang_code": "%s"' % lang, '"lang_code":"%s"' % lang)
    counter, lines = open_source(source)
    emit("start", lang=lang, total=counter.total, playable=len(words))
    shards = {}
    kept = seen = 0
    started = last_report = time.time()
    try:
        for line in lines:
            kept, seen = read_line(line, lang, marks, words, shards, kept, seen)
            now = time.time()
            if now - last_report > 0.5:
                last_report = now
                pct = " %d %%" % (100 * counter.done / counter.total) if counter.total else ""
                print("\r  %d entries read, %d kept%s   " % (seen, kept, pct), end="", file=sys.stderr)
                emit("progress", done=counter.done, total=counter.total, read=seen, kept=kept)
    except (EOFError, gzip.BadGzipFile, UnicodeDecodeError, zlib_error()) as e:
        raise InstallError("source", "unreadable download: %s" % e)
    print(file=sys.stderr)
    if kept == 0:
        raise InstallError("source", "no definitions found: the source doesn't look like a wiktextract extract for '%s'" % lang)
    emit("writing", kept=kept)
    write_pack(lang, source, out_dir, shards, kept, started)


def zlib_error():
    import zlib
    return zlib.error


def read_line(line, lang, marks, words, shards, kept, seen):
    # Cheap prefilter before parsing: entries of the chosen language only.
    if marks[0] not in line and marks[1] not in line:
        return kept, seen
    try:
        record = json.loads(line)
    except ValueError:
        return kept, seen
    if record.get("lang_code") != lang or not isinstance(record.get("word"), str):
        return kept, seen
    seen += 1
    key = fold(record["word"])
    if key is None or key not in words:
        return kept, seen
    entry = entry_from(record)
    if entry is None:
        return kept, seen
    shards.setdefault(key[:2], {}).setdefault(key, []).append(entry)
    return kept + 1, seen


def write_pack(lang, source, out_dir, shards, kept, started):
    parent = os.path.dirname(out_dir)
    try:
        tmp = tempfile.mkdtemp(prefix=".definitions-", dir=parent)
    except OSError as e:
        raise InstallError("disk", str(e))
    try:
        for prefix, data in shards.items():
            with open(os.path.join(tmp, prefix + ".json"), "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        manifest = {
            "format": PACK_FORMAT, "version": PACK_VERSION, "language": lang,
            "source": LANGUAGES[lang]["name"],
            "sourceUrl": source if re.match(r"^https?://", source) else "",
            "license": "CC BY-SA 4.0", "licenseUrl": "https://creativecommons.org/licenses/by-sa/4.0/",
            "builtAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "entries": kept, "words": sum(len(d) for d in shards.values()), "shards": sorted(shards),
        }
        with open(os.path.join(tmp, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
        if os.path.isdir(out_dir):
            shutil.rmtree(out_dir)
        os.rename(tmp, out_dir)
    except OSError as e:
        shutil.rmtree(tmp, ignore_errors=True)
        raise InstallError("disk", str(e))
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    size = sum(os.path.getsize(os.path.join(out_dir, f)) for f in os.listdir(out_dir))
    print("Installed in %s: %d words, %d entries, %.1f MB, in %d s"
          % (out_dir, manifest["words"], kept, size / 1e6, time.time() - started), file=sys.stderr)
    emit("done", words=manifest["words"], entries=kept, bytes=size, seconds=round(time.time() - started))


def remove_stale_temp(parent):
    """Leftovers of an interrupted run (a killed process can't clean up)."""
    try:
        names = os.listdir(parent)
    except OSError:
        return
    for name in names:
        path = os.path.join(parent, name)
        if name.startswith(".definitions-") and time.time() - os.path.getmtime(path) > 3600:
            shutil.rmtree(path, ignore_errors=True)


def main():
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    parser = argparse.ArgumentParser(description="Installs word definitions (Wiktionary) for Omascrabble.")
    parser.add_argument("--lang", choices=sorted(LANGUAGES), default="fr", help="game language (default: fr)")
    parser.add_argument("--source", default=os.environ.get("OMASCRABBLE_DEFINITIONS_SOURCE"),
                        help="wiktextract JSONL(.gz) URL or file (default: the Kaikki.org extract)")
    parser.add_argument("--progress-json", action="store_true", help="machine-readable progress on stdout")
    parser.add_argument("--lexicon", help="game word list (default: dictionary/data/open-<lang>.dawg)")
    parser.add_argument("--out", help="pack directory (default: $XDG_DATA_HOME/omascrabble/definitions/<lang>)")
    args = parser.parse_args()
    source = args.source or LANGUAGES[args.lang]["source"]
    lexicon = args.lexicon or os.path.join(PLUGIN, "dictionary", "data", "open-%s.dawg" % args.lang)
    out = args.out or os.path.join(data_home, "omascrabble", "definitions", args.lang)
    global JSON_PROGRESS
    JSON_PROGRESS = args.progress_json
    # Cancel from the game sends SIGTERM: unwind normally so temp files go.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    try:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        remove_stale_temp(os.path.dirname(out))
        build(args.lang, source, lexicon, out)
    except InstallError as e:
        emit("error", code=e.code, message=str(e))
        raise SystemExit("error: " + str(e))
    except OSError as e:
        emit("error", code="disk", message=str(e))
        raise SystemExit("error: " + str(e))


if __name__ == "__main__":
    main()
