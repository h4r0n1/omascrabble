import { applyAction, legalActions, createGame, MODE, END_REASON } from "../engine/game.mjs"
import { REASON } from "../engine/reasons.mjs"
import { newGame, setRack, placeWord, placementsFor, wordDictionary, tileConservation } from "./lib/fixtures.mjs"

export const name = "End game"

// Moves every tile left in the bag onto rows far from the centre.
function emptyBag(s) {
  const free = []
  for (let r = 0; r < 15; r++) {
    if (r >= 4 && r <= 10) continue
    for (let c = 0; c < 15; c++) if (s.board[r * 15 + c] === null) free.push(r * 15 + c)
  }
  let k = 0
  while (s.bag.length) s.board[free[k++]] = s.bag.pop()
}

export function register(t) {
  const dict = wordDictionary()

  t.test("bag empty and rack emptied ends the game", function() {
    const s = newGame()
    placeWord(s, "MAISON", 7, 2, "H")
    setRack(s, 0, "S")
    setRack(s, 1, "QZ")         // 8 + 10 left on the opponent's rack
    emptyBag(s)
    const scores = [s.players[0].score, s.players[1].score]
    const r = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "MAISONS", 7, 2, "H") }, { dictionary: dict })
    t.ok(r.ok, r.message)
    t.equal(r.state.status, "ended")
    t.equal(r.state.end.reason, END_REASON.OUT)
    t.deepEqual(r.state.end.adjustments, [18, -18])
    t.deepEqual(r.state.end.finalScores, [scores[0] + 8 + 18, scores[1] - 18])
    t.equal(r.state.end.winner, 0)
    t.ok(r.state.moves.length === 1 && r.state.moves[0].score === 8)
    t.equal(applyAction(r.state, { type: "pass", player: 1 }, {}).reason, REASON.GAME_OVER)
  })

  t.test("rack emptied while the bag still has tiles: play goes on", function() {
    const s = newGame()
    placeWord(s, "MAISON", 7, 2, "H")
    setRack(s, 0, "S")
    const r = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "MAISONS", 7, 2, "H") }, { dictionary: dict })
    t.ok(r.ok, r.message)
    t.equal(r.state.status, "active")
    t.equal(r.state.players[0].rack.length, 7)
  })

  t.test("repeated passes end the game", function() {
    let s = newGame()
    for (let i = 0; i < 6; i++) {
      t.equal(s.status, "active", "still playing before pass " + (i + 1))
      const r = applyAction(s, { type: "pass", player: s.current }, {})
      t.ok(r.ok, r.message)
      s = r.state
    }
    t.equal(s.status, "ended")
    t.equal(s.end.reason, END_REASON.SCORELESS)
    for (let p = 0; p < 2; p++) t.ok(s.end.adjustments[p] <= 0, "remaining tiles are subtracted")
    t.ok(tileConservation(s))
  })

  t.test("a scoring move resets the scoreless count", function() {
    let s = newGame()
    s = applyAction(s, { type: "pass", player: 0 }, {}).state
    setRack(s, 1, "MOTAEIU")
    s = applyAction(s, { type: "play", player: 1, placements: placementsFor(s, 1, "MOT", 7, 6, "H") }, { dictionary: dict }).state
    t.equal(s.scorelessTurns, 0)
  })

  t.test("time expiration ends the game", function() {
    let s = newGame({ rules: { time: { totalMs: 60000 } } })
    t.equal(applyAction(s, { type: "timeout", player: 0 }, {}).reason, REASON.TIME_NOT_EXPIRED)
    const r = applyAction(s, { type: "timeout", player: 0, elapsedMs: 60000 }, {})
    t.ok(r.ok, r.message)
    t.equal(r.state.end.reason, END_REASON.TIMEOUT)
    t.equal(r.state.players[0].timeUsedMs, 60000)
    t.ok(r.state.end.adjustments[0] < 0 && r.state.end.adjustments[1] < 0)
  })

  t.test("overtime penalty policy keeps playing and charges at the end", function() {
    let s = newGame({ rules: { time: { totalMs: 60000, onTimeout: "penalty", overtimePenaltyPerMinute: 10 } } })
    t.equal(applyAction(s, { type: "timeout", player: 0, elapsedMs: 70000 }, {}).reason, REASON.TIME_NOT_EXPIRED)
    s = applyAction(s, { type: "pass", player: 0, elapsedMs: 130000 }, {}).state // 70 s over → 2 started minutes
    s = applyAction(s, { type: "resign", player: 1 }, {}).state
    t.deepEqual(s.end.timePenalties, [20, 0])
  })

  t.test("resignation: the other player wins", function() {
    const s = newGame()
    s.players[1].score = 100
    const r = applyAction(s, { type: "resign", player: 1 }, {})
    t.ok(r.ok)
    t.equal(r.state.end.reason, END_REASON.RESIGN)
    t.equal(r.state.end.winner, 0)
    // resigning is allowed out of turn
    t.equal(applyAction(s, { type: "resign", player: 0 }, {}).state.end.winner, 1)
  })

  t.test("equal final scores are a draw", function() {
    let s = newGame()
    setRack(s, 0, "EE")
    setRack(s, 1, "EE")
    for (let i = 0; i < 6; i++) s = applyAction(s, { type: "pass", player: s.current }, {}).state
    t.equal(s.end.winner, null)
  })

  t.test("practice mode ends without a winner", function() {
    let s = createGame({ mode: MODE.PRACTICE, players: [{ name: "Solo", kind: "human" }], seed: 3 })
    for (let i = 0; i < 3; i++) s = applyAction(s, { type: "pass", player: 0 }, {}).state
    t.equal(s.status, "ended")
    t.equal(s.end.winner, null)
  })

  t.test("challenge: an invalid word is withdrawn", function() {
    const s = newGame({ rules: { validation: "challenge" } })
    setRack(s, 0, "MOXSAIE")
    const rackBefore = s.players[0].rack.slice()
    const played = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "MOX", 7, 6, "H") }, { dictionary: dict })
    t.ok(played.ok, "phony accepted provisionally: " + played.message)
    t.ok(played.state.players[0].score > 0)
    t.ok(legalActions(played.state, 1).challenge)
    const c = applyAction(played.state, { type: "challenge", player: 1 }, { dictionary: dict })
    t.ok(c.ok, c.message)
    t.equal(c.result.success, true)
    t.deepEqual(c.result.invalidWords, ["MOX"])
    t.equal(c.state.players[0].score, 0)
    t.deepEqual(c.state.players[0].rack, rackBefore)
    t.equal(c.state.bag.length, s.bag.length)
    t.equal(c.state.board.filter(function(x) { return x !== null }).length, 0)
    t.equal(c.state.current, 1, "the challenger plays next")
    t.ok(c.state.moves[0].withdrawn)
    t.ok(tileConservation(c.state))
  })

  t.test("challenge: a valid word stands, with the selected penalty", function() {
    const setup = function(penalty) {
      const s = newGame({ rules: { validation: "challenge", challenge: { penalty: penalty, penaltyPoints: 10 } } })
      setRack(s, 0, "MOTSAIE")
      return applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "MOT", 7, 6, "H") }, { dictionary: dict }).state
    }
    const none = applyAction(setup("none"), { type: "challenge", player: 1 }, { dictionary: dict })
    t.equal(none.result.success, false)
    t.equal(none.state.current, 1)
    t.equal(none.state.players[1].score, 0)
    const points = applyAction(setup("points"), { type: "challenge", player: 1 }, { dictionary: dict })
    t.equal(points.state.players[1].score, -10)
    t.equal(points.state.current, 1)
    const lose = applyAction(setup("lose_turn"), { type: "challenge", player: 1 }, { dictionary: dict })
    t.equal(lose.state.current, 0, "challenger loses the turn")
    t.equal(lose.state.players[0].score, 8)
  })

  t.test("challenge: playing on accepts the pending move", function() {
    const s = newGame({ rules: { validation: "challenge" } })
    setRack(s, 0, "MOXSAIE")
    let st = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "MOX", 7, 6, "H") }, { dictionary: dict }).state
    st = applyAction(st, { type: "pass", player: 1 }, {}).state
    t.equal(st.pending, null)
    t.equal(st.moves[0].provisional, false)
    t.equal(applyAction(st, { type: "challenge", player: 0 }, { dictionary: dict }).reason, REASON.NO_PENDING_MOVE)
  })

  t.test("challenge: going out waits for the opponent's verdict", function() {
    const s = newGame({ rules: { validation: "challenge" } })
    placeWord(s, "MAISON", 7, 2, "H")
    setRack(s, 0, "X")
    setRack(s, 1, "E")
    emptyBag(s)
    const out = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "MAISONX", 7, 2, "H") }, { dictionary: dict })
    t.ok(out.ok, out.message)
    t.equal(out.state.status, "active", "not over until accepted")
    t.equal(applyAction(out.state, { type: "pass", player: 1 }, {}).reason, REASON.CHALLENGE_PENDING)
    const accepted = applyAction(out.state, { type: "accept", player: 1 }, {})
    t.equal(accepted.state.status, "ended")
    const challenged = applyAction(out.state, { type: "challenge", player: 1 }, { dictionary: dict })
    t.equal(challenged.result.success, true)
    t.equal(challenged.state.status, "active")
    t.equal(challenged.state.players[0].rack.length, 1)
  })
}
