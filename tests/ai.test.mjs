import { MoveGenerator, boardArrays, rackCounts } from "../ai/movegen.mjs"
import { validateMove } from "../engine/validator.mjs"
import { boardFromState, rackTiles, publicView, applyAction } from "../engine/game.mjs"
import { letterValues, getTileset } from "../engine/tileset.mjs"
import { inBounds } from "../engine/board.mjs"
import { createRng, nextInt } from "../engine/rng.mjs"
import { newGame, setRack, placeWord, wordDictionary, tileConservation } from "./lib/fixtures.mjs"
import { buildDawg } from "../dictionary/dawg-builder.mjs"
import { TILE_ALPHABET } from "../dictionary/normalize.mjs"

export const name = "AI"

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const VALUES = (function() {
  const v = letterValues(getTileset("fr-classic"))
  return LETTERS.split("").map(function(l) { return v[l] })
})()

function allMoves(gen, state, player, options) {
  const view = publicView(state, player)
  const arrays = boardArrays(view.board)
  const moves = []
  gen.generate(arrays.board, arrays.blanks, rackCounts(view.rack), options || {}, {
    onMove: function(g) { moves.push(g.materialize()) }
  })
  return moves
}

function keyOf(tiles) {
  return tiles.map(function(t) { return t.row + "," + t.col + "," + t.letter + (t.blank ? "*" : "") }).sort().join("|")
}

// Turns generated tiles into engine placements using the player's rack.
function placementsOf(state, player, tiles) {
  const rack = state.players[player].rack.slice()
  return tiles.map(function(t) {
    const want = t.blank ? "?" : t.letter
    const i = rack.findIndex(function(id) { return state.tiles[id].letter === want })
    const id = rack.splice(i, 1)[0]
    return t.blank ? { tileId: id, row: t.row, col: t.col, jokerLetter: t.letter } : { tileId: id, row: t.row, col: t.col }
  })
}

// Every legal move for a small rack, by trying all placements through the
// engine's validator: the oracle for the generator.
function bruteForce(state, player, dict) {
  const board = boardFromState(state)
  const rack = rackTiles(state, player)
  const found = new Map()
  const letterChoices = function(tile) { return tile.isJoker ? LETTERS.split("") : [tile.letter] }
  const tryPlacements = function(cells, order) {
    // assign rack tiles (in `order`) to `cells`
    const lists = order.map(function(t) { return letterChoices(t) })
    const pick = function(k, acc) {
      if (k === cells.length) {
        const placements = cells.map(function(c, i) {
          const tile = order[i]
          return tile.isJoker ? { tileId: tile.id, row: c[0], col: c[1], jokerLetter: acc[i] } : { tileId: tile.id, row: c[0], col: c[1] }
        })
        const r = validateMove({ board: board, rack: rack, placements: placements, dictionary: dict, rules: state.rules, checkWords: true })
        if (r.valid) {
          const tiles = placements.map(function(p, i) { return { row: p.row, col: p.col, letter: acc[i], blank: order[i].isJoker } })
          found.set(keyOf(tiles), r.score)
        }
        return
      }
      for (const l of lists[k]) pick(k + 1, acc.concat([l]))
    }
    pick(0, [])
  }
  const perms = function(arr, k) {
    if (k === 0) return [[]]
    const out = []
    arr.forEach(function(x, i) {
      const rest = arr.slice(0, i).concat(arr.slice(i + 1))
      for (const p of perms(rest, k - 1)) out.push([x].concat(p))
    })
    return out
  }
  for (let size = 1; size <= rack.length; size++) {
    const orders = perms(rack, size)
    for (let r = 0; r < 15; r++) for (let c = 0; c < 15; c++) {
      for (const dir of size === 1 ? ["H"] : ["H", "V"]) {
        // `size` empty cells along dir starting at (r, c), skipping occupied ones
        const cells = []
        let rr = r, cc = c
        while (cells.length < size && inBounds(rr, cc)) {
          if (board.isEmpty(rr, cc)) cells.push([rr, cc])
          else if (cells.length === 0) break
          if (dir === "H") cc++; else rr++
        }
        if (cells.length < size || !board.isEmpty(r, c)) continue
        for (const order of orders) tryPlacements(cells, order)
      }
    }
  }
  return found
}

export function register(t) {
  const dict = wordDictionary()
  const gen = new MoveGenerator(dict.graph(), VALUES)

  t.test("opening moves cover the centre and score like the engine", function() {
    const s = newGame()
    setRack(s, 0, "MAISONS")
    const moves = allMoves(gen, s, 0)
    t.ok(moves.length > 0)
    const maison = moves.filter(function(m) { return m.word === "MAISONS" && m.dir === "H" })
    t.equal(maison.length, 7, "MAISONS can start at 7 columns and still cover the star")
    for (const m of moves) {
      t.ok(m.tiles.some(function(x) { return x.row === 7 && x.col === 7 }), "covers centre: " + m.word)
      const r = validateMove({ board: boardFromState(s), rack: rackTiles(s, 0), placements: placementsOf(s, 0, m.tiles), dictionary: dict, rules: s.rules })
      t.ok(r.valid, m.word + " " + r.message)
      t.equal(r.score, m.score, "score of " + m.word)
    }
  })

  t.test("generator equals the brute-force oracle (no board)", function() {
    const s = newGame()
    setRack(s, 0, "ETS")
    const oracle = bruteForce(s, 0, dict)
    const mine = new Map()
    for (const m of allMoves(gen, s, 0)) {
      const k = keyOf(m.tiles)
      t.ok(!mine.has(k), "duplicate move " + k)
      mine.set(k, m.score)
    }
    t.equal(mine.size, oracle.size)
    oracle.forEach(function(score, k) { t.equal(mine.get(k), score, k) })
  })

  t.test("generator equals the brute-force oracle (crowded board, joker)", function(ctx) {
    const s = newGame()
    placeWord(s, "MAISON", 7, 2, "H")
    placeWord(s, "OS", 5, 6, "V")   // (5,6),(6,6) above the O of MAISON: a column O-S-O
    placeWord(s, "TE", 8, 3, "H")
    // The oracle validates every placement one by one: keep it small on the
    // slower QML engine.
    setRack(s, 0, ctx.slow ? "?S" : "S?E")
    const oracle = bruteForce(s, 0, dict)
    const mine = new Map()
    for (const m of allMoves(gen, s, 0)) {
      const k = keyOf(m.tiles)
      t.ok(!mine.has(k), "duplicate move " + k)
      mine.set(k, m.score)
    }
    t.ok(oracle.size > 0)
    const missing = []
    oracle.forEach(function(score, k) { if (!mine.has(k)) missing.push(k) })
    const extra = []
    mine.forEach(function(score, k) { if (!oracle.has(k)) extra.push(k) })
    t.deepEqual(missing.slice(0, 5), [], "moves the generator missed")
    t.deepEqual(extra.slice(0, 5), [], "moves the oracle rejects")
    oracle.forEach(function(score, k) { if (mine.has(k)) t.equal(mine.get(k), score, k) })
  })

  t.test("vocabulary tiers limit the words formed", function() {
    const tiers = { MAISON: 3, MAISONS: 1, MAIS: 3, AS: 3, SA: 0, ON: 3, SON: 1, NOS: 2 }
    const graph = buildDawg(Object.keys(tiers), TILE_ALPHABET, { tierBits: 2, tierOf: function(w) { return tiers[w] } })
    const g = new MoveGenerator(graph, VALUES)
    const s = newGame()
    setRack(s, 0, "MAISONS")
    const all = allMoves(g, s, 0, { minTier: 0 }).map(function(m) { return m.word })
    const common = allMoves(g, s, 0, { minTier: 2 }).map(function(m) { return m.word })
    t.ok(all.indexOf("MAISONS") !== -1 && all.indexOf("SA") !== -1)
    t.ok(common.indexOf("MAISON") !== -1 && common.indexOf("NOS") !== -1)
    for (const w of ["MAISONS", "SA", "SON"]) t.ok(common.indexOf(w) === -1, w + " is beyond tier 2")
    // cross words obey the tier too: with SON on the board, hooking S… is fine,
    // but a move whose cross word is SA (tier 0) must not appear at minTier 2.
    placeWord(s, "S", 7, 7, "H")
    setRack(s, 0, "A")
    const hooks = allMoves(g, s, 0, { minTier: 2 })
    for (const m of hooks) t.ok(m.word !== "SA", "main word SA filtered")
    t.equal(allMoves(g, s, 0, { minTier: 0 }).filter(function(m) { return m.word === "SA" }).length, 2)
  })

  t.test("random self-play keeps every rule (generator vs engine)", function(ctx) {
    const rng = createRng(2026)
    for (let game = 0; game < 3; game++) {
      let s = newGame({ seed: 100 + game })
      let turns = 0
      while (s.status === "active" && turns < 60) {
        const p = s.current
        const moves = allMoves(gen, s, p)
        let action
        if (moves.length === 0) action = { type: "pass", player: p }
        else {
          const m = moves[nextInt(rng, moves.length)]
          action = { type: "play", player: p, placements: placementsOf(s, p, m.tiles) }
          const check = validateMove({ board: boardFromState(s), rack: rackTiles(s, p), placements: action.placements, dictionary: dict, rules: s.rules })
          t.ok(check.valid, "generated move rejected: " + m.word + " " + check.message)
          t.equal(check.score, m.score, "score mismatch for " + m.word)
        }
        const r = applyAction(s, action, { dictionary: dict })
        t.ok(r.ok, r.message)
        s = r.state
        t.ok(tileConservation(s))
        turns++
      }
    }
  })
}
