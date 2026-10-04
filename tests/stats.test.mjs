import { emptyStats, summarizeGame, recordGame, normalizeStats, deriveStats } from "../engine/stats.mjs"
import { applyAction, createGame, MODE } from "../engine/game.mjs"
import { newGame, setRack, placeWord, placementsFor, wordDictionary } from "./lib/fixtures.mjs"

export const name = "Stats"

function finishedGame(mode) {
  let s = newGame(mode ? { mode: mode } : {})
  if (mode === MODE.HUMAN_VS_AI) s.players[1].kind = "ai", s.players[1].difficulty = "expert"
  setRack(s, 0, "ARTISTE")
  s = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "ARTISTE", 7, 1, "H"), elapsedMs: 30000 }, { dictionary: wordDictionary() }).state
  s = applyAction(s, { type: "resign", player: 1 }, {}).state
  return s
}

export function register(t) {
  t.test("a game summary counts what the player did", function() {
    const sum = summarizeGame(finishedGame(MODE.HUMAN_VS_AI), 0)
    t.equal(sum.result, "win")
    t.equal(sum.scrabbles, 1)
    t.equal(sum.tilesPlayed, 7)
    t.deepEqual(sum.moveScores, [66])
    t.deepEqual(sum.bestWord, { word: "ARTISTE", notation: "ARTISTE", score: 66 }, "best move includes the bonus")
    t.equal(sum.difficulty, "expert")
    t.equal(sum.durationMs, 30000)
  })

  t.test("recording aggregates and never counts a game twice", function() {
    const game = finishedGame(MODE.HUMAN_VS_AI)
    let st = recordGame(emptyStats(), summarizeGame(game, 0))
    st = recordGame(st, summarizeGame(game, 0))
    t.equal(st.gamesPlayed, 1)
    t.equal(st.wins, 1)
    t.equal(st.bestDifficultyDefeated, "expert")
    t.equal(st.highestWord.score, 66)
    t.equal(deriveStats(st).winRate, 1)
  })

  t.test("local two-player games count as played, not as wins", function() {
    const st = recordGame(emptyStats(), summarizeGame(finishedGame(MODE.HUMAN_VS_HUMAN), 0))
    t.equal(st.gamesPlayed, 1)
    t.equal(st.wins + st.losses + st.draws, 0)
  })

  t.test("demonstration games are nobody's statistics", function() {
    const demo = createGame({ mode: MODE.AI_VS_AI, seed: 1, players: [{ name: "A", kind: "ai", difficulty: "expert" }, { name: "B", kind: "ai", difficulty: "beginner" }] })
    t.equal(demo.mode, MODE.AI_VS_AI)
    const ended = applyAction(demo, { type: "resign", player: 1 }, {}).state
    t.deepEqual(recordGame(emptyStats(), summarizeGame(ended, 0)), emptyStats())
  })

  t.test("broken stats files normalize to safe values", function() {
    const n = normalizeStats({ gamesPlayed: -4, wins: "3", highestWord: { word: "a b", score: 5 }, recent: [null, { gameId: "x" }], bestDifficultyDefeated: "god" })
    t.equal(n.gamesPlayed, 0)
    t.equal(n.wins, 0)
    t.equal(n.highestWord, null)
    t.equal(n.bestDifficultyDefeated, null)
    t.equal(n.recent.length, 1)
    t.deepEqual(normalizeStats(null), emptyStats())
  })
}
