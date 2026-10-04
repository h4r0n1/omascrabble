import { serializeGame, deserializeGame, migrateDocument, SAVE_ERROR, SAVE_VERSION } from "../engine/serializer.mjs"
import { applyAction } from "../engine/game.mjs"
import { newGame, setRack, placementsFor, wordDictionary } from "./lib/fixtures.mjs"

export const name = "Serializer"

function playedGame() {
  let s = newGame({ rules: { time: { totalMs: 20 * 60000 } } })
  setRack(s, 0, "MO?SAIE")
  s = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "MOt", 7, 6, "H"), elapsedMs: 4200 }, { dictionary: wordDictionary() }).state
  s = applyAction(s, { type: "pass", player: 1, elapsedMs: 1000 }, {}).state
  return s
}

function tamper(state, fn) {
  const doc = JSON.parse(serializeGame(state))
  fn(doc)
  return JSON.stringify(doc)
}

export function register(t) {
  t.test("round trip keeps the whole game", function() {
    const s = playedGame()
    const text = serializeGame(s)
    const back = deserializeGame(text)
    t.ok(back.ok, back.message + " " + back.detail)
    t.equal(serializeGame(back.state), text)
    t.equal(back.state.players[0].timeUsedMs, 4200)
    t.equal(back.state.jokerLetters[back.state.board[7 * 15 + 8]], "T")
    t.equal(back.migratedFrom, null)
  })

  t.test("the save names the fields the spec lists", function() {
    const doc = JSON.parse(serializeGame(playedGame()))
    for (const key of ["version", "gameId", "createdAt", "updatedAt", "mode", "dictionary", "players", "board", "bag", "racks", "scores", "turn", "timers", "moves", "settings"])
      t.ok(key in doc, "missing " + key)
    t.equal(doc.version, SAVE_VERSION)
  })

  t.test("a restored game plays on identically", function() {
    const s = playedGame()
    const back = deserializeGame(serializeGame(s)).state
    const a = applyAction(s, { type: "pass", player: 0 }, { now: 1 })
    const b = applyAction(back, { type: "pass", player: 0 }, { now: 1 })
    t.equal(serializeGame(a.state), serializeGame(b.state))
  })

  t.test("malformed and foreign files are refused", function() {
    t.equal(deserializeGame("").error, SAVE_ERROR.EMPTY)
    t.equal(deserializeGame("{").error, SAVE_ERROR.MALFORMED_JSON)
    t.equal(deserializeGame("[]").error, SAVE_ERROR.NOT_A_SAVE)
    t.equal(deserializeGame('{"hello": 1}').error, SAVE_ERROR.NOT_A_SAVE)
    t.equal(deserializeGame(null).error, SAVE_ERROR.EMPTY)
  })

  t.test("a newer save version is reported, not discarded", function() {
    const r = deserializeGame(tamper(playedGame(), function(d) { d.version = SAVE_VERSION + 1 }))
    t.equal(r.ok, false)
    t.equal(r.error, SAVE_ERROR.NEWER_VERSION)
  })

  t.test("tile conservation is enforced", function() {
    const dup = deserializeGame(tamper(playedGame(), function(d) { d.bag.push(d.racks[0][0]) }))
    t.equal(dup.error, SAVE_ERROR.CORRUPT)
    const lost = deserializeGame(tamper(playedGame(), function(d) { d.bag.pop() }))
    t.equal(lost.error, SAVE_ERROR.CORRUPT)
  })

  t.test("broken fields are refused", function() {
    const cases = [
      function(d) { d.scores[0] = "12" },
      function(d) { d.board[0].row = 20 },
      function(d) { d.board.find(function(c) { return c.jokerLetter }).jokerLetter = null },
      function(d) { d.tiles[3].points = 999 },
      function(d) { d.turn.current = 5 },
      function(d) { d.players.push({ name: "X", kind: "human" }) },
      function(d) { d.rng = { s: [1, 2] } },
      function(d) { d.moves[0].placements[0].row = -1 },
      function(d) { d.pending = { moveIndex: 1, player: 1, drawn: [], prevScoreless: 0, endsGame: false } },
      function(d) { d.mode = "online" },
      function(d) { d.status = "paused" },
      function(d) { d.racks[1] = d.racks[1].concat(d.bag.splice(0, 3)) }
    ]
    cases.forEach(function(fn, i) {
      const r = deserializeGame(tamper(playedGame(), fn))
      t.equal(r.error, SAVE_ERROR.CORRUPT, "case " + i)
    })
  })

  t.test("rules from a save are normalized", function() {
    const r = deserializeGame(tamper(playedGame(), function(d) { d.rules.bingoBonus = -5; d.rules.validation = "anything" }))
    t.ok(r.ok, r.detail)
    t.equal(r.state.rules.bingoBonus, 0)
    t.equal(r.state.rules.validation, "immediate")
  })

  t.test("migrations run in order and must advance", function() {
    const doc = { version: 1, steps: [] }
    const ok = migrateDocument(doc, {
      1: function(d) { d.steps.push(1); d.version = 2 },
      2: function(d) { d.steps.push(2); d.version = 3 }
    }, 3)
    t.ok(ok.ok)
    t.deepEqual(doc.steps, [1, 2])
    t.equal(migrateDocument({ version: 1 }, {}, 2).error, SAVE_ERROR.UNSUPPORTED_VERSION)
    t.equal(migrateDocument({ version: 1 }, { 1: function() {} }, 2).error, SAVE_ERROR.UNSUPPORTED_VERSION)
  })
}
