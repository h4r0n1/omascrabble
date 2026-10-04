// AIPlayer: picks an action from what a player may legitimately know — the
// board, its own rack, the bag size and the counts of unseen tiles (bag and
// opponent racks together). It never sees the bag order or an opponent's
// rack, and it submits an ordinary engine action that the GameEngine
// validates like any human move.
//
//   AIPlayer
//    ├── MoveGenerator       every legal move with its exact score
//    ├── CandidateGenerator  the short list worth judging
//    ├── MoveEvaluator       leave, board danger, premiums, endgame
//    └── DifficultyProfile   vocabulary, breadth, judgement, slips

import { MoveGenerator, boardArrays, rackCounts, BLANK } from "./movegen.mjs"
import { CandidateCollector, keyFunction } from "./candidates.mjs"
import { leaveValue, dangerOf, premiumUse, endgameAdjustment, rackValueOf } from "./evaluator.mjs"
import { profileFor } from "./difficulty.mjs"
import { createRng, nextFloat, nextInt, randomSeed } from "../engine/rng.mjs"
import { getTileset, letterValues } from "../engine/tileset.mjs"

const LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const N = 15

function valuesFor(rules) {
  const v = letterValues(getTileset(rules && rules.tileset ? rules.tileset : "fr-classic"))
  return LETTERS.split("").map(function(l) { return v[l] || 0 })
}

function unseenArray(unseen) {
  const counts = new Int8Array(27)
  for (const letter in unseen) {
    if (letter === "?") counts[BLANK] += unseen[letter]
    else counts[letter.charCodeAt(0) - 65] += unseen[letter]
  }
  return counts
}

// Placements for a generated move, taking tile ids from the rack.
export function placementsFor(move, rack) {
  const pool = rack.slice()
  return move.tiles.map(function(t) {
    const i = pool.findIndex(function(r) { return t.blank ? r.isJoker : (!r.isJoker && r.letter === t.letter) })
    if (i === -1) throw new Error("rack does not hold " + (t.blank ? "a joker" : t.letter))
    const tile = pool.splice(i, 1)[0]
    return t.blank ? { tileId: tile.id, row: t.row, col: t.col, jokerLetter: t.letter } : { tileId: tile.id, row: t.row, col: t.col }
  })
}

function applyToBoard(board, blanks, tiles) {
  const b = Int8Array.from(board)
  const k = Uint8Array.from(blanks)
  for (const t of tiles) {
    b[t.row * N + t.col] = t.letter.charCodeAt(0) - 65
    k[t.row * N + t.col] = t.blank ? 1 : 0
  }
  return { board: b, blanks: k }
}

// Draws `size` tiles from the unseen pool (counts) without replacement.
function sampleRack(rng, pool, size) {
  const bag = []
  for (let i = 0; i < 27; i++) for (let c = 0; c < pool[i]; c++) bag.push(i)
  const out = new Int8Array(27)
  for (let k = 0; k < size && bag.length; k++) {
    const j = nextInt(rng, bag.length)
    out[bag[j]]++
    bag[j] = bag[bag.length - 1]
    bag.pop()
  }
  return out
}

function bestScore(gen, board, blanks, rack, rules) {
  let best = 0
  gen.generate(board, blanks, rack, { bingoTiles: rules.bingoTiles, bingoBonus: rules.bingoBonus }, {
    onMove: function(g) { if (g.score > best) best = g.score }
  })
  return best
}

// Best letters to keep when exchanging: the subset with the highest leave.
function bestExchange(rack, rackSize) {
  const letters = []
  for (let i = 0; i < 27; i++) for (let c = 0; c < rack[i]; c++) letters.push(i)
  let best = null
  const total = 1 << letters.length
  for (let mask = 0; mask < total; mask++) {
    const keep = new Int8Array(27)
    let kept = 0
    for (let b = 0; b < letters.length; b++) if (mask & (1 << b)) { keep[letters[b]]++; kept++ }
    if (kept >= letters.length) continue // must give at least one
    const value = leaveValue(keep)
    if (!best || value > best.value) best = { value: value, keep: keep, kept: kept }
  }
  return best
}

function exchangeIds(rackTiles, keep) {
  const remaining = Int8Array.from(keep)
  const give = []
  for (const t of rackTiles) {
    const idx = t.isJoker ? BLANK : t.letter.charCodeAt(0) - 65
    if (remaining[idx] > 0) remaining[idx]--
    else give.push(t.id)
  }
  return give
}

// view: engine publicView(); profile: profileFor(); graph: the tile Dawg.
// options: { seed, now, deadline } — `deadline` (ms timestamp) bounds the
// look-ahead. Returns { action, info }.
export function chooseAction(view, profileOrName, graph, options) {
  const profile = typeof profileOrName === "string" ? profileFor(profileOrName) : profileOrName
  const opts = options || {}
  const clock = typeof opts.now === "function" ? opts.now : Date.now
  const started = clock()
  const deadline = Number.isFinite(opts.deadline) ? opts.deadline : started + profile.thinkMs[1]
  const rng = createRng(opts.seed === undefined || opts.seed === null ? randomSeed() : opts.seed)
  const rules = view.rules
  const values = valuesFor(rules)
  const gen = new MoveGenerator(graph, values)
  const arrays = boardArrays(view.board)
  const rack = rackCounts(view.rack)
  const unseen = unseenArray(view.unseen)
  const bagEmpty = view.bagCount === 0
  const opponentRack = bagEmpty && view.playerCount === 2 ? unseen : null
  const opponentRackValue = opponentRack ? rackValueOf(opponentRack, values) : 0

  const collector = new CandidateCollector(Math.max(profile.candidatePool, profile.simulation ? profile.simulation.candidates : 0) + 4,
    keyFunction(profile, { bagEmpty: bagEmpty }))
  gen.generate(arrays.board, arrays.blanks, rack, { minTier: profile.minTier, bingoTiles: rules.bingoTiles, bingoBonus: rules.bingoBonus }, collector)
  const moves = collector.moves()
  const info = { generated: collector.total, considered: moves.length, simulated: 0, difficulty: profile.id }

  // Full judgement on the short list.
  for (const m of moves) {
    let equity = m.score
    if (!bagEmpty) equity += profile.leaveWeight * leaveValue(m.leave)
    equity -= profile.defenseWeight * dangerOf(arrays.board, m.tiles)
    equity += profile.premiumWeight * premiumUse(m.tiles, values)
    if (bagEmpty && profile.endgame !== "none") equity += endgameAdjustment(m.leave, opponentRackValue, values)
    m.equity = equity
  }
  moves.sort(function(a, b) { return b.equity - a.equity })

  // Champion: test the leaders against what the opponent could answer.
  if (moves.length > 1 && (profile.simulation || (profile.endgame === "search" && opponentRack))) {
    const count = Math.min(moves.length, profile.simulation ? profile.simulation.candidates : 6)
    const leaders = moves.slice(0, count)
    const weight = profile.simulation ? profile.simulation.replyWeight : 1
    if (opponentRack) {
      // Endgame: the opponent's rack is exactly the unseen tiles.
      for (const m of leaders) {
        if (clock() > deadline) break
        const after = applyToBoard(arrays.board, arrays.blanks, m.tiles)
        let left = 0
        for (let i = 0; i < 27; i++) left += m.leave[i]
        const reply = left === 0 ? 0 : bestScore(gen, after.board, after.blanks, opponentRack, rules)
        m.equity -= weight * reply
        info.simulated++
      }
    } else if (profile.simulation) {
      const pool = Int8Array.from(unseen)
      const opponentSize = Math.min(rules.rackSize, view.rackCounts && view.rackCounts.length > 1 ? view.rackCounts[(view.me + 1) % view.rackCounts.length] : rules.rackSize)
      const samples = []
      for (let s = 0; s < profile.simulation.samples; s++) samples.push(sampleRack(rng, pool, opponentSize))
      const replies = leaders.map(function() { return { sum: 0, n: 0 } })
      let s = 0
      while (s < samples.length && clock() < deadline) {
        for (let k = 0; k < leaders.length && clock() < deadline; k++) {
          const after = applyToBoard(arrays.board, arrays.blanks, leaders[k].tiles)
          replies[k].sum += bestScore(gen, after.board, after.blanks, samples[s], rules)
          replies[k].n++
          info.simulated++
        }
        s++
      }
      // Compare candidates on the samples they all completed.
      const minN = Math.min.apply(null, replies.map(function(r) { return r.n }))
      if (minN > 0) {
        leaders.forEach(function(m, k) { m.equity -= weight * (replies[k].sum / replies[k].n) })
      }
    }
    moves.sort(function(a, b) { return b.equity - a.equity })
  }

  // Exchange when the rack is bad enough that a reset beats the best play.
  const canExchange = view.bagCount >= rules.exchangeMinBag
  if (canExchange && profile.exchangeWillingness > 0) {
    const ex = bestExchange(rack, rules.rackSize)
    const bestPlay = moves.length ? moves[0].equity : -Infinity
    const margin = 6 / profile.exchangeWillingness
    if (ex && ex.value * Math.max(profile.leaveWeight, 0.5) > bestPlay + margin) {
      const ids = exchangeIds(view.rack, ex.keep)
      if (ids.length > 0) {
        info.reason = "exchange"
        info.timeMs = clock() - started
        return { action: { type: "exchange", player: view.me, tileIds: ids }, info: info }
      }
    }
  }

  if (moves.length === 0) {
    info.timeMs = clock() - started
    if (canExchange) {
      const ex = bestExchange(rack, rules.rackSize)
      const ids = exchangeIds(view.rack, ex ? ex.keep : new Int8Array(27))
      if (ids.length > 0) {
        info.reason = "no-move-exchange"
        return { action: { type: "exchange", player: view.me, tileIds: ids }, info: info }
      }
    }
    info.reason = "no-move-pass"
    return { action: { type: "pass", player: view.me }, info: info }
  }

  // Choose according to the profile's temperament.
  let chosen = moves[0]
  const pool = moves.slice(0, Math.min(moves.length, profile.candidatePool))
  if (profile.pick === "weighted") {
    // Beginners pick among the pool, favouring the middle of the list.
    const weights = pool.map(function(m, i) { return 1 + Math.min(i, pool.length - 1 - i) })
    let total = 0
    for (const w of weights) total += w
    let x = nextFloat(rng) * total
    for (let i = 0; i < pool.length; i++) { x -= weights[i]; if (x <= 0) { chosen = pool[i]; break } }
  } else if (profile.pick === "top-random") {
    chosen = pool[Math.min(pool.length - 1, Math.floor(nextFloat(rng) * nextFloat(rng) * pool.length))]
  }
  if (profile.mistakeRate > 0 && nextFloat(rng) < profile.mistakeRate && moves.length > 2) {
    chosen = moves[Math.min(moves.length - 1, 1 + nextInt(rng, Math.min(moves.length - 1, 6)))]
    info.slip = true
  }

  info.reason = "play"
  info.timeMs = clock() - started
  info.word = chosen.word
  info.score = chosen.score
  info.equity = Math.round(chosen.equity * 10) / 10
  return { action: { type: "play", player: view.me, placements: placementsFor(chosen, view.rack) }, info: info }
}

// Should the AI challenge the pending move? `words` are the words it formed.
export function decideChallenge(words, profileOrName, dictionary, options) {
  const profile = typeof profileOrName === "string" ? profileFor(profileOrName) : profileOrName
  const rng = createRng(options && options.seed !== undefined ? options.seed : randomSeed())
  const invalid = words.some(function(w) { return !dictionary.isValid(w) })
  if (invalid) return nextFloat(rng) < profile.challengeAccuracy
  const unfamiliar = words.some(function(w) { return dictionary.tierOf(w) < profile.minTier })
  const rate = unfamiliar ? profile.falseChallengeRate * 3 : profile.falseChallengeRate
  return nextFloat(rng) < rate
}

// Top moves for a hint or for the "best move was…" reveal: full vocabulary,
// ranked by score.
export function topMoves(view, graph, count) {
  const values = valuesFor(view.rules)
  const gen = new MoveGenerator(graph, values)
  const arrays = boardArrays(view.board)
  const collector = new CandidateCollector(count || 5, function(g) { return g.score })
  gen.generate(arrays.board, arrays.blanks, rackCounts(view.rack), { bingoTiles: view.rules.bingoTiles, bingoBonus: view.rules.bingoBonus }, collector)
  return collector.moves().map(function(m) {
    return { word: m.word, score: m.score, dir: m.dir, row: m.row, col: m.col, tiles: m.tiles, placements: placementsFor(m, view.rack) }
  })
}
