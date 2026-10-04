import { chooseAction, decideChallenge, topMoves } from "../ai/player.mjs"
import { profileFor, DIFFICULTIES } from "../ai/difficulty.mjs"
import { leaveValue } from "../ai/evaluator.mjs"
import { decodeDawg } from "../dictionary/dawg.mjs"
import { createProvider } from "../dictionary/registry.mjs"
import { createGame, applyAction, publicView, previewMove, MODE } from "../engine/game.mjs"
import { newGame, setRack, placeWord, wordDictionary, tileConservation } from "./lib/fixtures.mjs"

export const name = "AI player"

let cached = null
function realDictionary(ctx) {
  if (!ctx.openLexicon) return null
  if (!cached) cached = createProvider("open-fr", decodeDawg(ctx.openLexicon))
  return cached
}

function aiGame(seed, a, b, dict) {
  return createGame({
    mode: MODE.HUMAN_VS_AI, seed: seed, dictionary: dict.describe(),
    players: [{ name: "IA 1", kind: "ai", difficulty: a }, { name: "IA 2", kind: "ai", difficulty: b }]
  })
}

// Plays a whole game between two profiles; returns the final state.
function playOut(t, state, dict, maxTurns, deadlineMs) {
  let s = state
  let turns = 0
  while (s.status === "active" && turns < maxTurns) {
    const p = s.current
    const profile = profileFor(s.players[p].difficulty)
    const view = publicView(s, p)
    const choice = chooseAction(view, profile, dict.graph(), { seed: 1000 + turns, deadline: Date.now() + deadlineMs })
    const r = applyAction(s, choice.action, { dictionary: dict })
    t.ok(r.ok, "AI action refused: " + r.message + " " + JSON.stringify(choice.info))
    if (!r.ok) break
    s = r.state
    t.ok(tileConservation(s), "tiles conserved")
    turns++
  }
  return s
}

export function register(t) {
  t.test("leave values prefer balance and good tiles", function() {
    const counts = function(letters) {
      const c = new Int8Array(27)
      for (const ch of letters) c[ch === "?" ? 26 : ch.charCodeAt(0) - 65]++
      return c
    }
    t.ok(leaveValue(counts("ERS")) > leaveValue(counts("UUV")))
    t.ok(leaveValue(counts("?")) > leaveValue(counts("S")))
    t.ok(leaveValue(counts("AEIO")) < leaveValue(counts("AENR")))
    t.ok(leaveValue(counts("Q")) < leaveValue(counts("QU")) + 1)
    t.equal(leaveValue(counts("")), 0)
  })

  t.test("the AI only sees public information", function() {
    const s = newGame()
    const view = publicView(s, 1)
    const text = JSON.stringify(view)
    t.ok(!("bag" in view), "no bag order")
    t.equal(view.rack.length, 7)
    for (const id of s.players[0].rack) t.ok(!view.rack.some(function(r) { return r.id === id }), "no opponent tile ids")
    let unseen = 0
    for (const k in view.unseen) unseen += view.unseen[k]
    t.equal(unseen, s.bag.length + 7, "unseen = bag + opponent rack, as counts only")
    t.ok(text.indexOf('"rng"') === -1, "no generator state")
  })

  t.test("every difficulty plays a legal opening (small lexicon)", function() {
    const dict = wordDictionary()
    for (const d of DIFFICULTIES) {
      const s = newGame()
      setRack(s, 0, "MAISONS")
      const choice = chooseAction(publicView(s, 0), profileFor(d), dict.graph(), { seed: 5 })
      t.equal(choice.action.type, "play", d)
      const r = applyAction(s, choice.action, { dictionary: dict })
      t.ok(r.ok, d + ": " + r.message)
    }
  })

  t.test("no move: exchange if the bag allows, else pass", function() {
    const dict = wordDictionary(["ZZ"])
    const s = newGame()
    setRack(s, 0, "QWKVYJX")
    const choice = chooseAction(publicView(s, 0), profileFor("expert"), dict.graph(), { seed: 1 })
    t.equal(choice.action.type, "exchange")
    t.ok(applyAction(s, choice.action, {}).ok)
    s.bag.splice(3)
    const late = chooseAction(publicView(s, 0), profileFor("expert"), dict.graph(), { seed: 1 })
    t.equal(late.action.type, "pass")
  })

  t.test("decisions are reproducible with a seed", function() {
    const dict = wordDictionary()
    const s = newGame()
    setRack(s, 0, "MAISONS")
    const a = chooseAction(publicView(s, 0), profileFor("beginner"), dict.graph(), { seed: 77 })
    const b = chooseAction(publicView(s, 0), profileFor("beginner"), dict.graph(), { seed: 77 })
    t.deepEqual(a.action, b.action)
  })

  t.test("hints list the top moves by score", function() {
    const dict = wordDictionary()
    const s = newGame()
    setRack(s, 0, "MAISONS")
    const hints = topMoves(publicView(s, 0), dict.graph(), 3)
    t.equal(hints.length, 3)
    t.ok(hints[0].score >= hints[1].score && hints[1].score >= hints[2].score)
    t.ok(previewMove(s, 0, hints[0].placements, dict).valid)
  })

  t.test("challenge decisions follow the profile", function() {
    const dict = wordDictionary()
    let caught = 0
    for (let i = 0; i < 50; i++) if (decideChallenge(["MOX"], "expert", dict, { seed: i })) caught++
    t.equal(caught, 50, "an expert always catches a phony")
    let wrong = 0
    for (let i = 0; i < 50; i++) if (decideChallenge(["MAISON"], "expert", dict, { seed: i })) wrong++
    t.equal(wrong, 0, "and never challenges a valid word")
    let beginner = 0
    for (let i = 0; i < 200; i++) if (decideChallenge(["MOX"], "beginner", dict, { seed: i })) beginner++
    t.ok(beginner > 50 && beginner < 150, "a beginner misses some phonies: " + beginner)
  })

  t.test("a beginner only forms common words (real lexicon)", function(ctx) {
    const dict = realDictionary(ctx)
    if (!dict) t.skip("dictionary data not provided")
    let s = aiGame(11, "beginner", "beginner", dict)
    for (let turn = 0; turn < (ctx.slow ? 4 : 10) && s.status === "active"; turn++) {
      const view = publicView(s, s.current)
      const choice = chooseAction(view, profileFor("beginner"), dict.graph(), { seed: turn })
      if (choice.action.type === "play") {
        const preview = previewMove(s, s.current, choice.action.placements, dict)
        t.ok(preview.valid, preview.message)
        for (const w of preview.formedWords) t.ok(dict.tierOf(w) >= 3, w + " is outside a beginner's vocabulary (tier " + dict.tierOf(w) + ")")
      }
      s = applyAction(s, choice.action, { dictionary: dict }).state
    }
  })

  t.test("complete AI games keep every rule (real lexicon)", function(ctx) {
    const dict = realDictionary(ctx)
    if (!dict) t.skip("dictionary data not provided")
    const pairs = ctx.slow ? [["expert", "beginner"]] : [["expert", "beginner"], ["casual", "expert"], ["beginner", "casual"]]
    let expertWins = 0
    pairs.forEach(function(pair, i) {
      const end = playOut(t, aiGame(200 + i, pair[0], pair[1], dict), dict, 80, 50)
      t.equal(end.status, "ended", pair.join(" vs ") + " finished")
      t.ok(end.end.finalScores.every(Number.isInteger))
      if (pair[0] === "expert" && end.end.winner === 0) expertWins++
      if (pair[1] === "expert" && end.end.winner === 1) expertWins++
    })
    t.ok(expertWins >= 1, "expert should win at least one of these games")
  })

  t.test("champion look-ahead runs within its deadline (real lexicon)", function(ctx) {
    const dict = realDictionary(ctx)
    if (!dict) t.skip("dictionary data not provided")
    let s = aiGame(31, "expert", "champion", dict)
    s = playOut(t, s, dict, 6, 50) // reach a mid-game position
    if (s.status !== "active") return
    s.current = 1
    const started = Date.now()
    const choice = chooseAction(publicView(s, 1), profileFor("champion"), dict.graph(), { seed: 3, deadline: started + 1500 })
    t.ok(Date.now() - started < 4000, "took " + (Date.now() - started) + " ms")
    t.ok(choice.info.simulated > 0 || choice.action.type !== "play", "look-ahead ran")
    t.ok(applyAction(s, choice.action, { dictionary: dict }).ok)
  })
}
