# Online play (in progress)

Two players on two Omarchy machines, invited by a link, with **no referee**:
both machines are equal, both run the whole game, and neither can see the
other's rack or the order of the bag. This is an optional add-on: the base
game keeps its one-line install and stays fully offline.

Status: the encrypted bag (`net/deck.py`) is done and tested. Everything
below it is the plan.

## Pieces

| Piece | Where | Job |
|---|---|---|
| Encrypted bag | `net/deck.py` | Shuffling, private draws, reveals, reshuffles, end audit. Pure Python, no I/O. |
| Online helper | `net/` (to do) | Python, standard library only, started by the game. Owns the keys and the bag, talks to the other machine, speaks JSON lines with the game on stdin/stdout. |
| Transport | helper (to do) | Tox through `libtoxcore` (ctypes, no compiling): invite links, no server, encrypted, works across the internet. A local socket transport for tests. |
| Game side | engine + controller (to do) | Tiles whose letter is unknown, moves applied on both machines, state fingerprints, the online screens. |

The user installs `toxcore` themselves (`sudo pacman -S toxcore`) when they
turn on online play; the game never runs sudo. Without it, everything else
works as today.

## No referee: both machines play the same game

Each machine holds a full copy of the game. A move travels as a small message
(tile handles and squares) and both machines apply it with the same engine,
the same rules and the same word list, so both reach the same state. After
every move each side sends a fingerprint of its state; a mismatch stops the
game with an error instead of letting the copies drift. Moves are numbered,
so after a disconnection the two sides swap what the other missed and carry
on; either player can resume.

The handshake checks that both run compatible versions and the same word list
(id and data version).

## The bag

See the module docstring of `net/deck.py` for the construction. In game terms:

- **Tiles have handles, not letters.** The engine's tile ids are the bag's
  handles. A tile's letter is filled in on a machine only when that player may
  know it.
- **Drawing.** Which handles a player draws comes from the shared game RNG
  (seeded by a commit-reveal between the two sides, so neither picks it). The
  bag is already shuffled by both players, so the RNG choosing positions
  reveals nothing. The other player's helper sends its key for those handles
  to the drawer only.
- **Playing.** The move carries the tiles' handles and letters; the other side
  checks every claim against the bag before applying the move.
- **Tiles going back into the bag.** On an exchange (draw first, then return)
  and when a challenged move is withdrawn (its replacement tiles go back), the
  player knows those tiles, so the two sides run a reshuffle: the bag gets new
  handles and nobody can follow a tile through it.
- **End of game.** The remaining racks are revealed (needed for the final
  adjustments), then every key is published and both sides audit the game:
  each tile existed exactly once and every claim was true. A failed audit
  marks the game as invalid on both machines.

## Clocks

Each machine times its own player and reports the time used with each move;
the other side checks the report against the time between messages, allowing
for network delay, and flags large differences.

## Who starts

Commit-reveal: each side sends the hash of a random value, then the value.
The combined value seeds the game RNG and picks the first player; neither side
can change its value after seeing the other's.

## Engine changes (to do)

- Tiles with an unknown letter (`letter: null`) and a way to fill letters in
  as they are revealed (copy-on-write, the tile map is shared between states).
- Unseen-tile counts from the tile set minus what the player can see, instead
  of adding up bag letters.
- `planDraw(state, player, count)`: the handles the next draw will take, so the
  helpers can deal before the move is applied.
- Exchanges and withdrawn moves accept the reshuffled bag (`newBag`) in online
  games.
- End of game waits for the racks to be revealed before computing the final
  adjustments.

## Messages between the two helpers (to do)

`hello` (versions, word list), `commit` / `open` (seed), `deck1`..`deck4`
(setup), `key` (private key for drawn handles), `move` (action + revealed
tiles + elapsed time + fingerprint), `reshuffle1`..`reshuffle4`, `racks` (end
reveal), `audit` (all keys), `resign`, `bye`. Big numbers travel as hex
strings. Every incoming message is checked (size, shape, order) and treated
as untrusted data.

## Performance

One modular exponentiation is about 9 ms at 1536 bits on a modest desktop.
Setup costs about 200 per machine (around 2 s each, one after the other); a
reshuffle about 2–3 s in total; a draw or reveal is instant. The game shows
"Shuffling the bag…" while it happens.

## Tests

    python3 -m unittest discover -s tests/net
