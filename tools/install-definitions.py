#!/usr/bin/env python3
"""Builds the optional definitions pack for Omascrabble.

    python3 tools/install-definitions.py            # download, build, install
    python3 tools/install-definitions.py --source extract.jsonl[.gz]

The definitions come from the Wiktionnaire (French Wiktionary), as extracted
by Kaikki.org (wiktextract), under CC BY-SA 4.0. The game never downloads
anything: this script does it once, on request, then writes small JSON shards
to $XDG_DATA_HOME/omascrabble/definitions (default ~/.local/share/...), which
the game reads offline.

Only French entries whose spelling is playable in the game's dictionary are
kept (the word list is read from the plugin's own dictionary/data/open-fr.dawg,
so the pack always matches the game), with at most three short definitions
each. The download (~700 MB compressed) is streamed and filtered on the fly;
nothing large is written to disk. Python 3 standard library only.
"""

import argparse
import base64
import gzip
import io
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.request

DEFAULT_SOURCE = "https://kaikki.org/frwiktionary/raw-wiktextract-data.jsonl.gz"
PACK_FORMAT = "omascrabble-definitions"
PACK_VERSION = 1
MAX_SENSES = 3
MAX_GLOSS = 240
HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(HERE)

# Same folding as dictionary/normalize.mjs: French diacritics and ligatures
# fold to tile letters; any other character makes the spelling unplayable.
FOLDS = {
    "à": "A", "â": "A", "ä": "A", "é": "E", "è": "E", "ê": "E", "ë": "E",
    "î": "I", "ï": "I", "ô": "O", "ö": "O", "ù": "U", "û": "U", "ü": "U",
    "ÿ": "Y", "ç": "C", "œ": "OE", "æ": "AE",
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
        senses = senses[:1]  # "Première personne … de siéger" — the base word carries the meaning
    entry = {"w": record["word"], "p": str(record.get("pos_title") or record.get("pos") or ""), "d": senses}
    if lemma and lemma != record["word"]:
        entry["of"] = lemma
    return entry


def open_source(source):
    if re.match(r"^https?://", source):
        print("Téléchargement de", source, file=sys.stderr)
        stream = urllib.request.urlopen(source, timeout=60)
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
        data = self.inner.read(len(b))
        n = len(data)
        b[:n] = data
        self.done += n
        return n


def build(source, lexicon, out_dir):
    words = read_lexicon(lexicon)
    print("Mots jouables :", len(words), file=sys.stderr)
    counter, lines = open_source(source)
    shards = {}
    kept = seen = 0
    started = last_report = time.time()
    for line in lines:
        # Cheap prefilter before parsing: French entries only.
        if '"lang_code": "fr"' not in line and '"lang_code":"fr"' not in line:
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if record.get("lang_code") != "fr" or not isinstance(record.get("word"), str):
            continue
        seen += 1
        key = fold(record["word"])
        if key is None or key not in words:
            continue
        entry = entry_from(record)
        if entry is None:
            continue
        shard = shards.setdefault(key[:2], {})
        shard.setdefault(key, []).append(entry)
        kept += 1
        now = time.time()
        if now - last_report > 2:
            last_report = now
            pct = " %d %%" % (100 * counter.done / counter.total) if counter.total else ""
            print("\r  %d entrées françaises lues, %d gardées%s   " % (seen, kept, pct), end="", file=sys.stderr)
    print(file=sys.stderr)
    if kept == 0:
        raise SystemExit("aucune définition trouvée : la source ne ressemble pas à un extrait du Wiktionnaire")

    tmp = tempfile.mkdtemp(prefix=".definitions-", dir=os.path.dirname(out_dir))
    try:
        for prefix, data in shards.items():
            with open(os.path.join(tmp, prefix + ".json"), "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        manifest = {
            "format": PACK_FORMAT, "version": PACK_VERSION,
            "source": "Wiktionnaire (fr.wiktionary.org), extrait par Kaikki.org / wiktextract",
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
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    size = sum(os.path.getsize(os.path.join(out_dir, f)) for f in os.listdir(out_dir))
    print("Installé dans %s : %d mots, %d entrées, %.1f Mo, en %d s"
          % (out_dir, manifest["words"], kept, size / 1e6, time.time() - started), file=sys.stderr)


def main():
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    parser = argparse.ArgumentParser(description="Installe les définitions (Wiktionnaire) pour Omascrabble.")
    parser.add_argument("--source", default=DEFAULT_SOURCE, help="URL ou fichier JSONL(.gz) wiktextract")
    parser.add_argument("--lexicon", default=os.path.join(PLUGIN, "dictionary", "data", "open-fr.dawg"))
    parser.add_argument("--out", default=os.path.join(data_home, "omascrabble", "definitions"))
    args = parser.parse_args()
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    build(args.source, args.lexicon, args.out)


if __name__ == "__main__":
    main()
