// Online play without a referee: two independent copies of the game, one per
// machine. A test "bag oracle" stands in for the encrypted bag (net/deck.py)
// and tells each copy only what that player may know. After every move both
// copies must agree (fingerprint) and neither may know the other's rack.

import {
  createGame, applyAction, publicView, revealTiles, replaceBag, completeEnd, fingerprint, tilesInPlay, unseenCounts, MODE
} from "../engine/game.mjs"
import { serializeGame, deserializeGame } from "../engine/serializer.mjs"
import { createTiles, getTileset } from "../engine/tileset.mjs"
import { createRng, nextInt } from "../engine/rng.mjs"
import { chooseAction } from "../ai/player.mjs"
import { decodeDawg } from "../dictionary/dawg.mjs"
import { createProvider } from "../dictionary/registry.mjs"
import { wordDictionary, tileConservation } from "./lib/fixtures.mjs"

export const name = "Online"

// The truth about each handle, known only to the oracle.
function makeOracle(n, seed) {
  const rng = createRng(seed)
  const order = []
  for (let i = 0; i < n; i++) order.push(i)
  for (let i = n - 1; i > 0; i--) { const j = nextInt(rng, i + 1); const t = order[i]; order[i] = order[j]; order[j] = t }
  const truth = {}
  order.forEach(function(index, handle) { truth[handle] = index })
  return {
    truth: truth,
    reveal: function(handles) { const out = {}; for (const h of handles) out[h] = truth[h]; return out },
    // Reshuffle: the bag's identities move to fresh handles in a new order.
    reshuffle: function(oldBag, firstHandle) {
      const ids = oldBag.map(function(h) { return truth[h] })
      for (let i = ids.length - 1; i > 0; i--) { const j = nextInt(rng, i + 1); const t = ids[i]; ids[i] = ids[j]; ids[j] = t }
      return ids.map(function(index, i) { truth[firstHandle + i] = index; return firstHandle + i })
    }
  }
}

function startPair(seed, rules) {
  const base = {
    mode: MODE.ONLINE, seed: seed, now: Date.UTC(2026, 9, 5, 12), gameId: "online-test-" + seed,
    players: [{ name: "Ana", kind: "human" }, { name: "Ben", kind: "human" }],
    dictionary: { id: "test", name: "Test", version: "test", official: false },
    rules: rules
  }
  let a = createGame(Object.assign({ online: { seat: 0, peerName: "Ben" } }, base))
  let b = createGame(Object.assign({ online: { seat: 1, peerName: "Ana" } }, base))
  const oracle = makeOracle(a.tiles.length, seed + 1)
  a = revealTiles(a, oracle.reveal(a.players[0].rack))
  b = revealTiles(b, oracle.reveal(b.players[1].rack))
  return { copies: [a, b], oracle: oracle }
}

function knows(state, id) { return !state.tiles[id].hidden }

// Plays one action on both copies the way the two machines would.
function step(t, pair, action, dict) {
  const actor = action.player
  const other = 1 - actor
  const mine = applyAction(pair.copies[actor], action, { dictionary: dict, now: 1 })
  t.ok(mine.ok, "actor's copy accepts: " + (mine.reason || ""))
  if (!mine.ok) return null
  // The move travels with the played tiles revealed (checked by the bag).
  let theirs = pair.copies[other]
  if (action.type === "play") theirs = revealTiles(theirs, pair.oracle.reveal(action.placements.map(function(p) { return p.tileId })))
  const res = applyAction(theirs, action, { dictionary: dict, now: 2 })
  t.ok(res.ok, "other copy accepts: " + (res.reason || ""))
  if (!res.ok) return null
  pair.copies[actor] = mine.state
  pair.copies[other] = res.state
  t.equal(fingerprint(pair.copies[0]), fingerprint(pair.copies[1]), "copies agree after " + action.type)
  const move = mine.state.moves[mine.state.moves.length - 1]
  // Drawn tiles: only the drawer learns them.
  if (move && move.drawn && move.drawn.length) pair.copies[actor] = revealTiles(pair.copies[actor], pair.oracle.reveal(move.drawn))
  // Tiles someone has seen went back to the bag: reshuffle.
  const rebag = action.type === "exchange" || (action.type === "challenge" && mine.result && mine.result.success)
  if (rebag) {
    const fresh = pair.oracle.reshuffle(pair.copies[0].bag, pair.copies[0].tiles.length)
    pair.copies = pair.copies.map(function(s) { return replaceBag(s, fresh) })
    t.equal(fingerprint(pair.copies[0]), fingerprint(pair.copies[1]), "copies agree after the reshuffle")
  }
  return move
}

function endBoth(t, pair) {
  // End-of-game reveal: every rack becomes known on both machines.
  const racks = [].concat(pair.copies[0].players[0].rack, pair.copies[0].players[1].rack)
  pair.copies = pair.copies.map(function(s) { return completeEnd(revealTiles(s, pair.oracle.reveal(racks))) })
  t.equal(JSON.stringify(pair.copies[0].end.finalScores), JSON.stringify(pair.copies[1].end.finalScores), "same final scores")
  t.equal(pair.copies[0].end.winner, pair.copies[1].end.winner, "same winner")
  t.ok(!pair.copies[0].end.awaitingReveal)
}

let realDict = null
function dictionaryFor(ctx) {
  if (ctx.openLexicon && !realDict) realDict = createProvider("open-fr", decodeDawg(ctx.openLexicon))
  return realDict
}

export function register(t) {
  t.test("tiles start hidden; each player sees only their rack", function() {
    const pair = startPair(11)
    const [a, b] = pair.copies
    t.equal(a.mode, MODE.ONLINE)
    t.ok(a.players[0].rack.every(function(id) { return knows(a, id) }))
    t.ok(a.players[1].rack.every(function(id) { return !knows(a, id) }), "A can't see B's rack")
    t.ok(b.players[0].rack.every(function(id) { return !knows(b, id) }), "B can't see A's rack")
    t.ok(a.bag.every(function(id) { return !knows(a, id) }), "nobody sees the bag")
    t.equal(fingerprint(a), fingerprint(b))
    // Unseen counts work from what the player can see.
    const counts = unseenCounts(a, 0)
    const total = Object.keys(counts).reduce(function(s, k) { return s + counts[k] }, 0)
    t.equal(total, a.tiles.length - 7)
  })

  t.test("reveals are checked and copy-on-write", function() {
    const pair = startPair(12)
    const a = pair.copies[0]
    const id = a.players[1].rack[0]
    const next = revealTiles(a, pair.oracle.reveal([id]))
    t.ok(knows(next, id) && !knows(a, id), "the old state is untouched")
    t.throws(function() { revealTiles(next, { [id]: (pair.oracle.truth[id] + 1) % 102 }) }, "a tile can't change identity")
    t.throws(function() { revealTiles(a, { 9999: 1 }) })
  })

  t.test("a reshuffle retires the bag and keeps every tile once", function() {
    const pair = startPair(13)
    const a = pair.copies[0]
    const fresh = pair.oracle.reshuffle(a.bag, a.tiles.length)
    const next = replaceBag(a, fresh)
    t.equal(next.bag.length, a.bag.length)
    t.ok(a.bag.every(function(id) { return next.tiles[id].retired }))
    t.equal(tilesInPlay(next).length, 102)
    t.throws(function() { replaceBag(a, fresh.slice(1)) })
    t.throws(function() { replaceBag(a, fresh.map(function(h) { return h + 5 })) })
    const round = deserializeGame(serializeGame(next))
    t.ok(round.ok, round.detail)
    t.equal(fingerprint(round.state), fingerprint(next))
  })

  t.test("a whole online game: both copies agree to the end (real lexicon)", function(ctx) {
    const dict = dictionaryFor(ctx)
    if (!dict) t.skip("dictionary data not provided")
    const pair = startPair(21)
    let turns = 0
    let exchanges = 0
    while (pair.copies[0].status === "active" && turns < 70) {
      const p = pair.copies[0].current
      const view = publicView(pair.copies[p], p)
      let action = chooseAction(view, "casual", dict.graph(), { seed: 100 + turns, deadline: Date.now() + 40 }).action
      // Exercise the reshuffle path a few times.
      if (turns % 6 === 5 && pair.copies[p].bag.length >= 7) {
        action = { type: "exchange", player: p, tileIds: pair.copies[p].players[p].rack.slice(0, 2) }
        exchanges++
      }
      step(t, pair, action, dict)
      // Nobody ever knows the opponent's rack before the end.
      if (pair.copies[0].status === "active") {
        t.ok(pair.copies[0].players[1].rack.every(function(id) { return !knows(pair.copies[0], id) }), "A never sees B's rack")
        t.ok(pair.copies[1].players[0].rack.every(function(id) { return !knows(pair.copies[1], id) }), "B never sees A's rack")
      }
      turns++
    }
    t.ok(exchanges > 0, "exchanges happened")
    if (pair.copies[0].status === "active") {
      step(t, pair, { type: "resign", player: pair.copies[0].current }, dict)
    }
    t.ok(pair.copies[0].end.awaitingReveal, "the end waits for the racks")
    endBoth(t, pair)
    // A saved online game loads back.
    const round = deserializeGame(serializeGame(pair.copies[1]))
    t.ok(round.ok, round.detail)
    t.equal(round.state.online.seat, 1)
  })

  t.test("challenge mode: a withdrawn move's draws go back and the bag is reshuffled", function() {
    const dict = wordDictionary(["MOT", "MOTS"])
    const pair = startPair(31, { validation: "challenge" })
    // Find what A holds and play its first two tiles as a (probably bogus) word.
    const a = pair.copies[0]
    const p = a.current
    const rack = pair.copies[p].players[p].rack
    const action = { type: "play", player: p, placements: [{ tileId: rack[0], row: 7, col: 7 }, { tileId: rack[1], row: 7, col: 8 }] }
    for (const pl of action.placements) if (pair.copies[p].tiles[pl.tileId].isJoker) pl.jokerLetter = "Z"
    const move = step(t, pair, action, dict)
    t.ok(move && move.provisional, "played provisionally")
    const word = move.words[0].word
    const out = step(t, pair, { type: "challenge", player: 1 - p }, dict)
    t.ok(out, "challenge applied")
    if (word !== "MOT" && word !== "MOTS") {
      t.ok(pair.copies[0].moves[move.index].withdrawn, "withdrawn")
      t.equal(fingerprint(pair.copies[0]), fingerprint(pair.copies[1]))
      t.equal(tilesInPlay(pair.copies[0]).length, 102)
    }
  })
}
