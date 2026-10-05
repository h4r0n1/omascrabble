# Omascrabble

A classic Scrabble game, in French or English, for **Omarchy Quattro**, built as a native
`omarchy-shell` panel plugin: QML/QtQuick inside the shell you already run, no
browser, no Electron, no server, fully offline.

- Classic rules: 15 × 15 board, premium squares, jokers, crossing words, the
  50-point bingo bonus, exchanges, passes, challenges, clocks, end-of-game
  adjustments.
- Two game languages, chosen per game: French (102 tiles, French values, an
  open French word list) or English (100 tiles, English values, an open
  English word list).
- Three modes: against the computer, two players at one keyboard, solo
  practice (hints and "best possible move" after each turn). A
  computer-vs-computer demonstration is available over IPC.
- A real algorithmic AI (no LLM) at four levels — Beginner, Casual, Expert,
  Champion — that sees only what a player may see, with rack values tuned for
  each language.
- Keyboard-first, mouse and drag-and-drop too; follows the Omarchy theme.
- French or English interface (or follow the system language), independent
  of the game language.

> Independent community project. SCRABBLE® is a trademark of its respective
> owners; this game is neither affiliated with nor endorsed by them, and uses
> no official artwork.

## 1. Requirements

- Omarchy 4 (Quattro) with its `omarchy-shell` (Quickshell, Qt 6). Tested on
  Omarchy 4.0.4, Quickshell 0.3, Qt 6.11.
- Nothing else for play: no network, no extra packages. Sounds use
  QtMultimedia, which a stock Omarchy already has; without it the game simply
  stays silent.
- Optional word definitions: `python3` (standard library only, present on a
  stock Omarchy) and a one-time download from kaikki.org (Wiktionary data,
  CC BY-SA 4.0), started only when you click *Download* or run
  `tools/download-definitions.py`.
- Development only: Node 18+ (tests, dictionary build), Python 3 (sound
  generation).
- No `sudo`, no system packages, no services. The plugin writes only to
  `~/.local/state/omascrabble` (saves, settings, statistics) and, if you
  download definitions, `~/.local/share/omascrabble`.

## 2. Installation

```bash
omarchy plugin add https://github.com/h4r0n1/omascrabble.git --enable
```

`omarchy plugin add` clones the repository into
`~/.config/omarchy/plugins/omascrabble` and validates the manifest; without
`--enable` it asks before enabling. A local checkout works as the URL too.
Installing changes nothing else on the system: the keybinding and menu entry
below are optional and added by you.

## 3. Enabling and opening

```bash
omarchy plugin enable omascrabble
omarchy-shell shell toggle omascrabble     # open / close the game
```

Bind the toggle to a key in `~/.config/hypr/bindings.lua`, for example:

```lua
o.bind("SUPER + SHIFT + ALT + S", "Scrabble", "omarchy-shell shell toggle omascrabble")
```

and/or add it to the Omarchy menu in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"scrabble": {"icon":"󰊗","label":"Scrabble","action":"omarchy-shell shell toggle omascrabble"},
```

The game opens as a regular window (title `Omascrabble`); Hyprland floats it by
default.

## 4. Disabling

```bash
omarchy plugin disable omascrabble
```

## 5. Removing

```bash
omarchy plugin remove omascrabble
rm -rf ~/.local/state/omascrabble          # saved game, settings, statistics
rm -rf ~/.local/share/omascrabble          # downloaded definitions, if any
```

Remove the keybinding or menu entry you added by hand, if any. Nothing else
is left behind.

## Updating

```bash
omarchy plugin update omascrabble
omarchy restart shell
```

The game stays loaded between openings (`keepLoaded`), and the shell keeps
running the code it compiled until it restarts — so restart the shell after an
update. The game shows a banner when the installed version is newer than the
running one.

## 6. Local development

```bash
git clone <repository> && cd <repository>
omarchy plugin validate .
node tests/run.mjs                    # engine, AI and dictionary tests (Node)
tests/run-qml.sh                      # the same suites under Qt's QML engine
dev/preview.sh midgame 1180 860       # offscreen render with your Omarchy theme
omarchy plugin add . && omarchy plugin enable omascrabble
```

`dev/preview.sh` runs a separate, short-lived Quickshell on the offscreen
platform with a temporary state directory: it never touches the running shell
or your saves. Scenarios: `home setup start midgame pending narrow practice
hvh challenge end settings stats joker exchange flow keys challenge-ai corrupt
nodict timeout`. `PREVIEW_THEME=<omarchy theme>`, `PREVIEW_APPEARANCE=light|dark`
and `PREVIEW_HC=1` vary the look.

Don't develop inside `~/.config/omarchy/plugins/`: every file change there
makes the shell reload all plugins.

Layout:

```
Scrabble.qml            panel entry point (lifecycle, window, error boundary, IPC)
manifest.json
app/                    services container, settings, desktop preferences, sounds
controller/             GameController: UI ↔ engine, AI orchestration, clocks
engine/                 pure JS (.mjs): board, tiles, rules, validator, scoring,
                        game state machine, save format, statistics
dictionary/             DictionaryProvider, DAWG reader, open lexicon, ODS 9 slot,
                        policies/, data/ (MPL-2.0)
ai/                     MoveGenerator, CandidateGenerator, MoveEvaluator,
                        DifficultyProfile, AIPlayer, WorkerScript entry
storage/                SaveManager
components/             QML UI: board, tiles, rack, screens, dialogs
tools/                  build-dictionary.mjs, gen-sounds.py
tests/                  suites shared by Node and Qt
dev/                    offscreen preview harness, benchmarks
```

The engine never touches the UI and the UI never decides a rule: every move
goes through `engine/game.mjs` `applyAction()`, which re-validates it.

## 7. Testing

```bash
node tests/run.mjs [filter]
tests/run-qml.sh
```

Covered: board geometry and premium layout, placement rules, every scoring
rule (premiums, stacking, cross words, jokers, bingo), the 102-tile bag and
determinism, every validation refusal, end-game conditions (out, passes,
timeout, resignation), challenges and penalties, save round-trips and
corruption, the dictionary format and its integrity checks, the move generator
against a brute-force oracle, AI legality across complete games, statistics and
settings. Tests use fixed seeds.

## 8. Dictionary setup

Two open word lists are bundled, one per game language. *New game* →
*Game language* picks the tile set, the word list and the notation together.

**English — Open Word List**: 246 093 playable words compiled from
[SCOWL](http://wordlist.aspell.net/) 2020.12.07 (size 80, all English
spellings — American, British, Canadian, Australian; MIT-like licence, see
[`dictionary/data/LICENSE-SCOWL.txt`](dictionary/data/LICENSE-SCOWL.txt)). It
is **neither TWL nor Collins Scrabble Words**: it is a spell-checker list, so
some tournament words are missing and a few it accepts aren't in either list.
Rebuild it with `node tools/build-dictionary.mjs --lang en --download`.

**Collins.** Like ODS 9 below, Collins Scrabble Words is licensed and not
included; a slot is ready for `~/.local/share/omascrabble/dictionaries/collins.dawg`
(id `collins`, language `en`, `"official": true`).

English games use the English notation: columns A–O, rows 1–15; `8H` is a
horizontal word from row 8, column H, and `H8` a vertical one. French games
keep the French notation: rows A–O, columns 1–15; `H8` horizontal, `8H`
vertical.

**Français — Open Lexicon**: 407 142 playable words
compiled from Grammalecte's *Lexique des formes fléchies du français* 7.7
(MPL-2.0). It is **not** the Officiel du Scrabble (ODS): some ODS words are
missing and some words ODS rejects are accepted. It includes interjections,
regional words and slang the source contains. See
[`dictionary/data/README.md`](dictionary/data/README.md) for provenance and the
selection policy, and rebuild it with:

```bash
node tools/build-dictionary.mjs --download
```

Accents fold to tile letters (é → E, ç → C, œ → OE); an entry with any other
character (hyphen, apostrophe, ñ…) is left out rather than stripped.

**ODS 9.** The official list is licensed and not included. With a licence, a
`DictionaryProvider` slot is ready: compile the list into the game's format as
`~/.local/share/omascrabble/dictionaries/ods9.dawg` (id `ods9`,
`"official": true`, tile alphabet), and "Français — ODS 9 · Officiel" becomes
selectable in *New game*. Nothing else changes.

### Definitions (optional)

Click a word in the history, the last-move panel or the end-of-game lists to
see its definitions. They come from **Wiktionary** (CC BY-SA 4.0, extracted by
Kaikki.org) — the French Wiktionnaire for French games, the English Wiktionary
for English games — as optional packs, one per game language.

Install them from the game: **Download** in the definitions dialog, or
*Settings → Definitions*, which lists both packs with their state and a
**Remove** button. The download shows its progress, can be cancelled, and
carries on if you close the window. It needs `python3` (standard library
only) and a network connection, once; French is about 740 MB, English about
520 MB, streamed and filtered on the fly — only entries playable in that
language's word list are kept (up to three short definitions each, with a
link from an inflected form to its base word), written as small JSON shards
to `~/.local/share/omascrabble/definitions/<lang>`. The game then reads them
offline.

The same thing from a terminal:

```bash
python3 ~/.config/omarchy/plugins/omascrabble/tools/download-definitions.py            # French
python3 ~/.config/omarchy/plugins/omascrabble/tools/download-definitions.py --lang en  # English
```

## 9. Configuration

Everything is in the game's *Settings* (*Réglages*): interface language
(Français, English, or automatic from the system locale), appearance (follow Omarchy, light,
dark, system), animations (automatic follows the desktop's reduced-motion
preference), gameplay toggles, AI difficulty / thinking time / personality,
accessibility (high contrast, larger tiles and text, premium labels — MT MD
LT LD in French, TW DW TL DL in English — and ★) and every keyboard shortcut.
The interface language and the game language are independent: an English
game in a French interface works, and so does the reverse.

Default keys: `Enter` play · `Esc` recall tiles · `Espace` take/put a tile ·
arrows move · `Tab` rack → board → buttons · letters on the board place tiles ·
`R` shuffle · `P` pass · `E` exchange · `C` challenge · `N` new game ·
`Ctrl+S` save · `H` hint · `Y` history · `F1` help. Hyprland's SUPER bindings
are never intercepted.

Files, all under `~/.local/state/omascrabble/`: `game.json` (versioned
save, written after every move), `settings.json`, `stats.json`, `archive/`
(finished games), `quarantine/` (files that could not be read — kept, never
deleted).

*Statistics → Reset* clears every statistic and record after a confirmation.
The previous numbers are kept in `stats-backup.json` (one copy, replaced at
each reset; copy it back over `stats.json` while the game is closed to undo);
archived games are not deleted.

IPC, for scripts and keybindings:

```bash
omarchy-shell shell call omascrabble status ""
omarchy-shell shell call omascrabble newGame '{"mode":"human_vs_ai","difficulty":"expert"}'
omarchy-shell shell call omascrabble demo '{"difficulty":"expert","difficulty2":"casual"}'
omarchy-shell shell call omascrabble snapshot ""   # PNG in $XDG_RUNTIME_DIR
```

## 10. Troubleshooting

- **The window doesn't open:** `omarchy plugin list` should show
  `omascrabble` enabled; then `omarchy-shell shell toggle omascrabble`.
- **An update has no effect:** `omarchy restart shell` (see *Updating*).
- **"Dictionary not found" / "Dictionnaire introuvable":** the data files are missing or damaged;
  `omarchy plugin update omascrabble` or reinstall.
- **"A saved file couldn’t be read" / "Une sauvegarde n'a pas pu être lue":** the file was moved to
  `~/.local/state/omascrabble/quarantine/`; nothing was deleted.
- **Logs:** `quickshell log -p /usr/share/omarchy/shell -t 100 | grep -i scrabble`.
  A single `QObject::connect(QJSEngine, QtObject): invalid nullptr parameter`
  warning comes from Qt's WorkerScript under Quickshell and is harmless.
- A game error can't take the shell down: the UI loads behind an error
  boundary, the AI runs on its own thread, and engine calls are guarded.

## Licence

Code: MIT ([LICENSE](LICENSE)). Dictionary data in `dictionary/data/`: the
French list is MPL-2.0 (Grammalecte), the English list is under SCOWL's
MIT-like licence ([`LICENSE-SCOWL.txt`](dictionary/data/LICENSE-SCOWL.txt)).
Optional definition packs, built on your machine, are CC BY-SA 4.0
(Wiktionary). Sounds are original, generated by `tools/gen-sounds.py`.
