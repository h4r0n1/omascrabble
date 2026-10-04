import { getTileset, createTiles, tileCount, letterValues } from "../engine/tileset.mjs"
import { createRng, nextInt, nextUint32, cloneRng } from "../engine/rng.mjs"
import { applyAction, tileView } from "../engine/game.mjs"
import { serializeGame } from "../engine/serializer.mjs"
import { REASON } from "../engine/reasons.mjs"
import { newGame, setRack, placeWord, placementsFor, tileConservation } from "./lib/fixtures.mjs"

export const name = "Bag"

const EXPECTED = {
  A: [9, 1], B: [2, 3], C: [2, 3], D: [3, 2], E: [15, 1], F: [2, 4], G: [2, 2], H: [2, 4], I: [8, 1],
  J: [1, 8], K: [1, 10], L: [5, 1], M: [3, 2], N: [6, 1], O: [6, 1], P: [2, 3], Q: [1, 8], R: [6, 1],
  S: [6, 1], T: [6, 1], U: [6, 1], V: [2, 4], W: [1, 10], X: [1, 10], Y: [1, 10], Z: [1, 10], "?": [2, 0]
}

export function register(t) {
  const set = getTileset("fr-classic")

  t.test("exactly 102 tiles", function() {
    t.equal(tileCount(set), 102)
    t.equal(createTiles(set).length, 102)
    const s = newGame()
    t.equal(s.bag.length + s.players[0].rack.length + s.players[1].rack.length, 102)
  })

  t.test("French distribution and values", function() {
    const counts = {}
    for (const tile of createTiles(set)) {
      counts[tile.letter] = (counts[tile.letter] || 0) + 1
      t.equal(tile.points, EXPECTED[tile.letter][1], "points of " + tile.letter)
      t.equal(tile.isJoker, tile.letter === "?")
    }
    for (const letter in EXPECTED) t.equal(counts[letter], EXPECTED[letter][0], "count of " + letter)
    t.equal(letterValues(set)["?"], 0)
  })

  t.test("no duplicate tile identity", function() {
    const ids = createTiles(set).map(function(x) { return x.id })
    t.equal(new Set(ids).size, 102)
    const s = newGame()
    t.ok(tileConservation(s))
  })

  t.test("each player draws a full rack", function() {
    const s = newGame()
    t.equal(s.players[0].rack.length, 7)
    t.equal(s.players[1].rack.length, 7)
    t.equal(s.bag.length, 88)
    const v = tileView(s, s.players[1].rack[3])
    t.equal(v.owner, 1)
    t.deepEqual(v.position, { zone: "rack", player: 1, index: 3 })
    t.equal(tileView(s, s.bag[0]).position.zone, "bag")
  })

  t.test("draws are deterministic for a seed", function() {
    t.equal(serializeGame(newGame({ seed: 7 })), serializeGame(newGame({ seed: 7 })))
    t.ok(serializeGame(newGame({ seed: 7 })) !== serializeGame(newGame({ seed: 8 })))
  })

  t.test("seeded generator is uniform enough and resumable", function() {
    const rng = createRng("seed")
    const buckets = [0, 0, 0, 0, 0, 0, 0]
    for (let i = 0; i < 7000; i++) buckets[nextInt(rng, 7)]++
    for (const b of buckets) t.ok(b > 850 && b < 1150, "bucket " + b)
    const copy = cloneRng(rng)
    t.equal(nextUint32(rng), nextUint32(copy))
  })

  t.test("exchange swaps tiles with the bag", function() {
    const s = newGame()
    const before = s.players[0].rack.slice()
    const give = before.slice(0, 3)
    const r = applyAction(s, { type: "exchange", player: 0, tileIds: give }, {})
    t.ok(r.ok, r.message)
    const after = r.state.players[0].rack
    t.equal(after.length, 7)
    t.equal(r.state.bag.length, s.bag.length)
    for (const id of give) {
      t.ok(after.indexOf(id) === -1, "exchanged tile left the rack")
      t.ok(r.state.bag.indexOf(id) !== -1, "exchanged tile is in the bag")
    }
    t.equal(r.state.current, 1)
    t.equal(r.state.scorelessTurns, 1)
    t.ok(tileConservation(r.state))
    t.equal(r.state.moves[0].type, "exchange")
  })

  t.test("exchange needs at least 7 tiles in the bag", function() {
    const s = newGame()
    s.bag.splice(6) // 6 left; the removed tiles go on the board edge to keep conservation
    // (conservation is irrelevant here: the engine must refuse before touching anything)
    const r = applyAction(s, { type: "exchange", player: 0, tileIds: [s.players[0].rack[0]] }, {})
    t.equal(r.ok, false)
    t.equal(r.reason, REASON.BAG_TOO_SMALL)
  })

  t.test("exchange input is checked", function() {
    const s = newGame()
    const mine = s.players[0].rack
    t.equal(applyAction(s, { type: "exchange", player: 0, tileIds: [] }, {}).reason, REASON.NOTHING_TO_EXCHANGE)
    t.equal(applyAction(s, { type: "exchange", player: 0, tileIds: [mine[0], mine[0]] }, {}).reason, REASON.DUPLICATE_TILE)
    t.equal(applyAction(s, { type: "exchange", player: 0, tileIds: [s.players[1].rack[0]] }, {}).reason, REASON.TILE_NOT_OWNED)
    t.equal(applyAction(s, { type: "exchange", player: 1, tileIds: [s.players[1].rack[0]] }, {}).reason, REASON.NOT_YOUR_TURN)
  })

  t.test("an empty bag simply stops drawing", function() {
    const s = newGame()
    placeWord(s, "MA", 7, 6, "H")
    setRack(s, 0, "SEIRTUA")
    // Park the rest of the bag on rows far from the centre (0-3, 11-14).
    const free = []
    for (let r = 0; r < 15; r++) {
      if (r >= 4 && r <= 10) continue
      for (let c = 0; c < 15; c++) free.push(r * 15 + c)
    }
    let k = 0
    while (s.bag.length) s.board[free[k++]] = s.bag.pop()
    t.ok(tileConservation(s))
    const r = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "SE", 7, 8, "H") },
                          { dictionary: { isValid: function() { return true } } })
    t.ok(r.ok, r.message)
    t.equal(r.state.bag.length, 0)
    t.equal(r.state.players[0].rack.length, 5, "nothing left to draw")
    t.equal(r.state.status, "active")
    t.ok(tileConservation(r.state))
  })
}
