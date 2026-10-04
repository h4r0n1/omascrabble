// Statistics: a summary per finished game, folded into running aggregates.
//
// "You" are player 0 in vs-AI and practice games. Local two-player games
// count as played and feed the word and score records, but not wins/losses:
// both players sit at the same keyboard.

import { MODE, END_REASON } from "./game.mjs"

export const STATS_VERSION = 1
export const DIFFICULTY_RANK = Object.freeze({ beginner: 1, casual: 2, expert: 3, champion: 4 })

export function emptyStats() {
  return {
    version: STATS_VERSION,
    gamesPlayed: 0,
    byMode: { human_vs_ai: 0, human_vs_human: 0, practice: 0 },
    wins: 0,
    losses: 0,
    draws: 0,
    totalScore: 0,
    scoredGames: 0,
    highestScore: null,       // { score, gameId, date }
    highestWord: null,        // { word, notation, score, gameId, date }
    scrabbles: 0,
    totalMoveScore: 0,
    scoringMoves: 0,
    bestDifficultyDefeated: null,
    totalDurationMs: 0,
    tilesPlayed: 0,
    exchanges: 0,
    passes: 0,
    challenges: 0,
    recent: []                // last summaries, newest first
  }
}

function durationOf(state) {
  const start = Date.parse(state.createdAt)
  const end = state.end && state.end.endedAt ? Date.parse(state.end.endedAt) : Date.parse(state.updatedAt)
  const wall = isFinite(start) && isFinite(end) ? Math.max(0, end - start) : 0
  let played = 0
  for (const p of state.players) played += p.timeUsedMs || 0
  return played > 0 ? played : wall
}

// Summarises a finished game from the point of view of `me` (default 0).
export function summarizeGame(state, me) {
  const self = Number.isInteger(me) ? me : 0
  const mine = state.moves.filter(function(m) { return m.player === self })
  const plays = mine.filter(function(m) { return m.type === "play" && !m.withdrawn })
  // The best "word" is the best move: what the player scored with it,
  // Scrabble bonus included, named after its main word.
  let best = null
  for (const m of plays) {
    const main = m.words[0]
    if (main && (!best || m.score > best.score)) best = { word: main.word, notation: main.notation || main.word, score: m.score }
  }
  let tiles = 0
  for (const m of plays) tiles += m.placements.length
  const final = state.end ? state.end.finalScores : state.players.map(function(p) { return p.score })
  let result = "solo"
  if (state.players.length > 1) {
    if (!state.end || state.end.winner === null) result = "draw"
    else result = state.end.winner === self ? "win" : "loss"
  }
  const opponent = state.players.length > 1 ? state.players[(self + 1) % state.players.length] : null
  return {
    gameId: state.gameId,
    mode: state.mode,
    date: state.end && state.end.endedAt ? state.end.endedAt : state.updatedAt,
    durationMs: durationOf(state),
    endReason: state.end ? state.end.reason : null,
    result: result,
    score: final[self],
    opponentScore: opponent ? final[(self + 1) % state.players.length] : null,
    opponentName: opponent ? opponent.name : null,
    difficulty: opponent && opponent.kind === "ai" ? opponent.difficulty : null,
    scrabbles: plays.filter(function(m) { return m.bingo }).length,
    bestWord: best,
    moveScores: plays.map(function(m) { return m.score }),
    tilesPlayed: tiles,
    exchanges: mine.filter(function(m) { return m.type === "exchange" }).length,
    passes: mine.filter(function(m) { return m.type === "pass" }).length,
    challenges: mine.filter(function(m) { return m.type === "challenge" }).length,
    resigned: !!(state.end && state.end.reason === END_REASON.RESIGN && state.end.actor === self)
  }
}

export function recordGame(stats, summary) {
  const s = normalizeStats(stats)
  if (s.recent.some(function(r) { return r.gameId === summary.gameId })) return s // already counted
  s.gamesPlayed++
  if (s.byMode[summary.mode] !== undefined) s.byMode[summary.mode]++
  const competitive = summary.mode === MODE.HUMAN_VS_AI
  if (competitive) {
    if (summary.result === "win") s.wins++
    else if (summary.result === "loss") s.losses++
    else if (summary.result === "draw") s.draws++
    if (summary.result === "win" && summary.difficulty && DIFFICULTY_RANK[summary.difficulty]) {
      const prev = s.bestDifficultyDefeated ? DIFFICULTY_RANK[s.bestDifficultyDefeated] || 0 : 0
      if (DIFFICULTY_RANK[summary.difficulty] > prev) s.bestDifficultyDefeated = summary.difficulty
    }
  }
  if (Number.isInteger(summary.score)) {
    s.totalScore += summary.score
    s.scoredGames++
    if (!s.highestScore || summary.score > s.highestScore.score)
      s.highestScore = { score: summary.score, gameId: summary.gameId, date: summary.date }
  }
  if (summary.bestWord && (!s.highestWord || summary.bestWord.score > s.highestWord.score))
    s.highestWord = { word: summary.bestWord.word, notation: summary.bestWord.notation, score: summary.bestWord.score, gameId: summary.gameId, date: summary.date }
  s.scrabbles += summary.scrabbles
  for (const v of summary.moveScores) { s.totalMoveScore += v; s.scoringMoves++ }
  s.totalDurationMs += summary.durationMs || 0
  s.tilesPlayed += summary.tilesPlayed
  s.exchanges += summary.exchanges
  s.passes += summary.passes
  s.challenges += summary.challenges
  const compact = Object.assign({}, summary)
  delete compact.moveScores
  s.recent = [compact].concat(s.recent).slice(0, 30)
  return s
}

// Derived figures for display.
export function deriveStats(stats) {
  const s = normalizeStats(stats)
  return {
    averageScore: s.scoredGames ? Math.round(s.totalScore / s.scoredGames) : 0,
    averageMoveScore: s.scoringMoves ? Math.round(s.totalMoveScore / s.scoringMoves * 10) / 10 : 0,
    averageDurationMs: s.gamesPlayed ? Math.round(s.totalDurationMs / s.gamesPlayed) : 0,
    winRate: (s.wins + s.losses + s.draws) ? s.wins / (s.wins + s.losses + s.draws) : 0
  }
}

// Coerces a loaded stats object into a valid one; unknown or broken fields
// fall back to empty values rather than poisoning the aggregates.
export function normalizeStats(input) {
  const base = emptyStats()
  if (!input || typeof input !== "object" || Array.isArray(input)) return base
  const num = function(v) { return Number.isFinite(v) && v >= 0 ? Math.round(v) : 0 }
  const keys = ["gamesPlayed", "wins", "losses", "draws", "scoredGames", "scrabbles", "totalMoveScore", "scoringMoves",
    "totalDurationMs", "tilesPlayed", "exchanges", "passes", "challenges"]
  for (const k of keys) base[k] = num(input[k])
  base.totalScore = Number.isFinite(input.totalScore) ? Math.round(input.totalScore) : 0
  if (input.byMode && typeof input.byMode === "object")
    for (const m in base.byMode) base.byMode[m] = num(input.byMode[m])
  if (input.highestScore && Number.isFinite(input.highestScore.score))
    base.highestScore = { score: Math.round(input.highestScore.score), gameId: String(input.highestScore.gameId || ""), date: String(input.highestScore.date || "") }
  if (input.highestWord && typeof input.highestWord.word === "string" && /^[A-Z]{2,15}$/.test(input.highestWord.word) && Number.isFinite(input.highestWord.score))
    base.highestWord = {
      word: input.highestWord.word, notation: String(input.highestWord.notation || input.highestWord.word).slice(0, 40),
      score: Math.round(input.highestWord.score), gameId: String(input.highestWord.gameId || ""), date: String(input.highestWord.date || "")
    }
  if (typeof input.bestDifficultyDefeated === "string" && DIFFICULTY_RANK[input.bestDifficultyDefeated])
    base.bestDifficultyDefeated = input.bestDifficultyDefeated
  if (Array.isArray(input.recent))
    base.recent = input.recent.filter(function(r) { return r && typeof r === "object" && typeof r.gameId === "string" }).slice(0, 30)
  return base
}
