# Dictionary data — Français — Open Lexicon

| File | Contents |
| --- | --- |
| `open-fr.dawg` | The 407 142 playable tile spellings (A–Z, 2–15 letters) with a frequency tier per word, as a compact DAWG. Used for play and by the AI. |
| `open-fr.forms.dawg` | The 437 308 accented spellings (été, cœur…), used only to show a word's French spelling. |

## Source and licence

These files are a compiled form of the **Lexique des formes fléchies du
français**, version 7.7, by Olivier R. for the Dicollecte / Grammalecte
project, published under the **Mozilla Public License 2.0**:

- Source archive: <https://grammalecte.net/dic/lexique-grammalecte-fr-v7.7.zip>
  (SHA-256 `bdccf2065e252010253171000a38de84581407896b6bc60aca7d4d69dab7e4d2`)
- Project: <https://grammalecte.net/>
- Licence text: [`LICENSE-MPL-2.0.txt`](LICENSE-MPL-2.0.txt), or
  <https://mozilla.org/MPL/2.0/>

This Source Code Form is subject to the terms of the Mozilla Public License,
v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at https://mozilla.org/MPL/2.0/. The source form of the data is the
lexicon above; `tools/build-dictionary.mjs` regenerates these files from it.

## This is not the ODS

The official French Scrabble reference is *L'Officiel du Scrabble* (ODS 9 for
2024–2027), whose electronic word list is licensed and is **not** included
here. The open lexicon is a different word list: it misses some words the ODS
accepts and accepts some it does not. The game labels it "Français — Open
Lexicon" and never presents it as official.

## How the words were selected

`dictionary/policies/open-fr.json` is the lexical policy:

- Entries are folded to tile letters: French accents and the ligatures
  œ/æ fold (é → E, ç → C, œ → OE). An entry containing any other character
  — a hyphen, an apostrophe, a digit, ñ, ø… — is **dropped, not stripped**.
- Removed: proper nouns, first names and surnames (`npr`, `prn`, `patr`),
  prefixes and suffixes, fragments of locutions, symbols, abbreviations,
  acronyms and ordinals, and capitalised forms.
- Kept: every spelling variant (traditional and 1990 reformed spellings,
  regional words, slang, archaic forms), as the ODS also accepts both
  spellings.
- Frequency tiers (0 rare … 3 very common) come from Grammalecte's frequency
  index of the most frequent spelling, with short words (≤ 3 letters) lowered
  by 2 points because corpus counts of short strings are noisy. Only the AI
  vocabulary profiles use them.

## Rebuilding

```bash
node tools/build-dictionary.mjs --download   # fetches and verifies the archive
```

The build is deterministic: the same source and policy produce byte-identical
files.
