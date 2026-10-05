// GameSerializer: the versioned save format.
//
// A save file is untrusted input. deserializeGame() parses it, migrates older
// format versions forward, and validates every field the engine relies on —
// including that each tile exists exactly once across board, racks and bag —
// before handing back a state. It never throws and never "repairs" quietly:
// anything wrong comes back as { ok: false, error, message } so the caller can
// keep the file aside and tell the player (an incompatible save is never
// silently discarded).

import { STATE_VERSION, STATUS, MODE, END_REASON } from "./game.mjs"
import { normalizeRules } from "./rules.mjs"
import { isRngState } from "./rng.mjs"
import { CELL_COUNT, inBounds, cellIndex } from "./board.mjs"

export const SAVE_FORMAT = "omascrabble-save"
export const SAVE_VERSION = 1

// MIGRATIONS[n] upgrades a version-n document to version n+1, in place.
// Add an entry for every format bump; deserializeGame applies them in order.
export const MIGRATIONS = {}

export const SAVE_ERROR = Object.freeze({
  EMPTY: "EMPTY",
  MALFORMED_JSON: "MALFORMED_JSON",
  NOT_A_SAVE: "NOT_A_SAVE",
  NEWER_VERSION: "NEWER_VERSION",
  UNSUPPORTED_VERSION: "UNSUPPORTED_VERSION",
  CORRUPT: "CORRUPT"
})

// Developer-facing; players see the "save.<CODE>" catalog strings.
const ERROR_MESSAGES = {
  EMPTY: "Save file is empty.",
  MALFORMED_JSON: "Save file is not valid JSON.",
  NOT_A_SAVE: "Not an Omascrabble save.",
  NEWER_VERSION: "Save comes from a newer version.",
  UNSUPPORTED_VERSION: "Save format no longer supported.",
  CORRUPT: "Save is incomplete or damaged."
}

function failure(code, detail) {
  return { ok: false, error: code, message: ERROR_MESSAGES[code] || "Invalid save.", detail: detail || "" }
}

class CorruptSave extends Error {}

function check(condition, detail) {
  if (!condition) throw new CorruptSave(detail)
}

const isInt = Number.isInteger
const isObj = function(v) { return !!v && typeof v === "object" && !Array.isArray(v) }
const isStr = function(v, max) { return typeof v === "string" && v.length <= (max || 200) }

export function serializeGame(state) {
  const board = []
  for (let i = 0; i < CELL_COUNT; i++) {
    const id = state.board[i]
    if (id === null || id === undefined) continue
    const t = state.tiles[id]
    board.push({ row: Math.floor(i / 15), col: i % 15, tileId: id, jokerLetter: t.isJoker ? (state.jokerLetters[id] || null) : null })
  }
  const doc = {
    format: SAVE_FORMAT,
    version: SAVE_VERSION,
    gameId: state.gameId,
    createdAt: state.createdAt,
    updatedAt: state.updatedAt,
    mode: state.mode,
    dictionary: state.dictionary,
    players: state.players.map(function(p) { return { name: p.name, kind: p.kind, difficulty: p.difficulty } }),
    board: board,
    bag: state.bag,
    racks: state.players.map(function(p) { return p.rack }),
    scores: state.players.map(function(p) { return p.score }),
    turn: { current: state.current, number: state.turn, scorelessTurns: state.scorelessTurns },
    timers: { usedMs: state.players.map(function(p) { return p.timeUsedMs }) },
    moves: state.moves,
    pending: state.pending,
    status: state.status,
    end: state.end,
    rules: state.rules,
    tiles: state.tiles,
    rng: state.rng,
    settings: state.settings,
    online: state.online || null
  }
  return JSON.stringify(doc)
}

// Online games carry hidden tiles (letter not known to this player) and
// retired ones (replaced by a reshuffle); their handles grow with every
// reshuffle, hence the higher limit.
function validateTiles(tiles, online) {
  check(Array.isArray(tiles) && tiles.length >= 2 && tiles.length <= (online ? 5000 : 200), "tiles")
  return tiles.map(function(t, i) {
    check(isObj(t) && t.id === i, "tile id " + i)
    if (online && t.hidden === true) return { id: i, letter: null, points: 0, isJoker: false, hidden: true, retired: t.retired === true }
    if (online) check(isInt(t.index) && t.index >= 0 && t.index < 200, "tile index " + i)
    check(typeof t.isJoker === "boolean", "tile isJoker " + i)
    check(t.isJoker ? t.letter === "?" : (typeof t.letter === "string" && /^[A-Z]$/.test(t.letter)), "tile letter " + i)
    check(isInt(t.points) && t.points >= 0 && t.points <= 50, "tile points " + i)
    check(!t.isJoker || t.points === 0, "joker points " + i)
    const out = { id: t.id, letter: t.letter, points: t.points, isJoker: t.isJoker }
    if (online) out.index = t.index
    return out
  })
}

function validIdList(list, tileCount, label) {
  check(Array.isArray(list), label)
  for (const id of list) check(isInt(id) && id >= 0 && id < tileCount, label + " id")
  return list.slice()
}

function validateMoves(moves, playerCount, tileCount) {
  check(Array.isArray(moves) && moves.length <= 2000, "moves")
  const types = ["play", "pass", "exchange", "challenge", "resign", "timeout"]
  return moves.map(function(m, i) {
    check(isObj(m) && types.indexOf(m.type) !== -1, "move type " + i)
    check(isInt(m.player) && m.player >= 0 && m.player < playerCount, "move player " + i)
    check(isInt(m.score), "move score " + i)
    if (m.type === "play") {
      check(Array.isArray(m.placements) && m.placements.length > 0, "move placements " + i)
      for (const pl of m.placements) {
        check(isObj(pl) && isInt(pl.tileId) && pl.tileId >= 0 && pl.tileId < tileCount, "placement tile " + i)
        check(inBounds(pl.row, pl.col), "placement cell " + i)
        check(typeof pl.letter === "string" && /^[A-Z]$/.test(pl.letter), "placement letter " + i)
      }
      check(Array.isArray(m.words) && m.words.length > 0, "move words " + i)
      for (const w of m.words) check(isObj(w) && isStr(w.word, 15) && /^[A-Z]+$/.test(w.word) && isInt(w.score), "move word " + i)
      validIdList(m.rackBefore || [], tileCount, "move rackBefore " + i)
      validIdList(m.drawn || [], tileCount, "move drawn " + i)
    }
    return m
  })
}

function buildState(doc) {
  check(isStr(doc.gameId, 100) && doc.gameId.length > 0, "gameId")
  check(Object.keys(MODE).map(function(k) { return MODE[k] }).indexOf(doc.mode) !== -1, "mode")
  let online = null
  if (doc.mode === MODE.ONLINE) {
    check(isObj(doc.online) && (doc.online.seat === 0 || doc.online.seat === 1), "online")
    online = { seat: doc.online.seat, peerName: isStr(doc.online.peerName, 40) ? doc.online.peerName : "" }
  }
  const tiles = validateTiles(doc.tiles, !!online)
  const n = tiles.length
  const rules = normalizeRules(doc.rules)

  check(Array.isArray(doc.players) && doc.players.length >= 1 && doc.players.length <= 4, "players")
  const pc = doc.players.length
  check(Array.isArray(doc.racks) && doc.racks.length === pc, "racks")
  check(Array.isArray(doc.scores) && doc.scores.length === pc, "scores")
  check(isObj(doc.timers) && Array.isArray(doc.timers.usedMs) && doc.timers.usedMs.length === pc, "timers")

  const seen = new Array(n).fill(0)
  const boardArr = new Array(CELL_COUNT).fill(null)
  const jokerLetters = {}
  check(Array.isArray(doc.board) && doc.board.length <= CELL_COUNT, "board")
  for (const cell of doc.board) {
    check(isObj(cell) && inBounds(cell.row, cell.col), "board cell")
    check(isInt(cell.tileId) && cell.tileId >= 0 && cell.tileId < n, "board tile")
    const idx = cellIndex(cell.row, cell.col)
    check(boardArr[idx] === null, "board duplicate cell")
    boardArr[idx] = cell.tileId
    seen[cell.tileId]++
    if (tiles[cell.tileId].isJoker) {
      check(typeof cell.jokerLetter === "string" && /^[A-Z]$/.test(cell.jokerLetter), "joker letter")
      jokerLetters[cell.tileId] = cell.jokerLetter
    }
  }

  const players = doc.players.map(function(p, i) {
    check(isObj(p) && isStr(p.name, 40) && (p.kind === "human" || p.kind === "ai"), "player " + i)
    check(p.difficulty === null || p.difficulty === undefined || isStr(p.difficulty, 20), "player difficulty " + i)
    const rack = validIdList(doc.racks[i], n, "rack " + i)
    check(rack.length <= rules.rackSize, "rack size " + i)
    for (const id of rack) seen[id]++
    check(isInt(doc.scores[i]) && Math.abs(doc.scores[i]) < 100000, "score " + i)
    const used = doc.timers.usedMs[i]
    check(typeof used === "number" && isFinite(used) && used >= 0, "timer " + i)
    return { name: p.name, kind: p.kind, difficulty: p.kind === "ai" ? (p.difficulty || null) : null, score: doc.scores[i], rack: rack, timeUsedMs: Math.round(used) }
  })

  const bag = validIdList(doc.bag, n, "bag")
  for (const id of bag) seen[id]++
  for (let i = 0; i < n; i++) check(seen[i] === (tiles[i].retired ? 0 : 1), "tile " + i + " appears " + seen[i] + " times")

  check(isObj(doc.turn) && isInt(doc.turn.current) && doc.turn.current >= 0 && doc.turn.current < pc, "turn")
  check(isInt(doc.turn.number) && doc.turn.number >= 1, "turn number")
  check(isInt(doc.turn.scorelessTurns) && doc.turn.scorelessTurns >= 0, "scoreless turns")
  check(isRngState(doc.rng), "rng")
  check(doc.status === STATUS.ACTIVE || doc.status === STATUS.ENDED, "status")

  const moves = validateMoves(doc.moves, pc, n)

  let pending = null
  if (doc.pending !== null && doc.pending !== undefined) {
    const p = doc.pending
    check(isObj(p) && isInt(p.moveIndex) && p.moveIndex >= 0 && p.moveIndex < moves.length, "pending")
    check(moves[p.moveIndex].type === "play" && isInt(p.player) && p.player === moves[p.moveIndex].player, "pending move")
    check(isInt(p.prevScoreless) && p.prevScoreless >= 0 && typeof p.endsGame === "boolean", "pending fields")
    pending = { moveIndex: p.moveIndex, player: p.player, drawn: validIdList(p.drawn || [], n, "pending drawn"), prevScoreless: p.prevScoreless, endsGame: p.endsGame }
  }

  let end = null
  if (doc.status === STATUS.ENDED) {
    const e = doc.end
    const reasons = Object.keys(END_REASON).map(function(k) { return END_REASON[k] })
    check(isObj(e) && reasons.indexOf(e.reason) !== -1, "end")
    check(!e.awaitingReveal || online, "end awaiting reveal")
    check(Array.isArray(e.finalScores) && e.finalScores.length === pc && e.finalScores.every(isInt), "end scores")
    check(e.winner === null || (isInt(e.winner) && e.winner >= 0 && e.winner < pc), "end winner")
    end = e
  }

  const dictionary = isObj(doc.dictionary) ? doc.dictionary : {}
  return {
    version: STATE_VERSION,
    gameId: doc.gameId,
    createdAt: isStr(doc.createdAt, 40) ? doc.createdAt : new Date(0).toISOString(),
    updatedAt: isStr(doc.updatedAt, 40) ? doc.updatedAt : new Date(0).toISOString(),
    mode: doc.mode,
    rules: rules,
    dictionary: {
      id: isStr(dictionary.id, 64) ? dictionary.id : "",
      name: isStr(dictionary.name, 120) ? dictionary.name : "",
      version: isStr(dictionary.version, 64) ? dictionary.version : "",
      official: dictionary.official === true
    },
    rng: { seed: isInt(doc.rng.seed) ? doc.rng.seed >>> 0 : 0, s: doc.rng.s.slice() },
    tiles: tiles,
    board: boardArr,
    jokerLetters: jokerLetters,
    bag: bag,
    players: players,
    current: doc.turn.current,
    turn: doc.turn.number,
    scorelessTurns: doc.turn.scorelessTurns,
    moves: moves,
    pending: pending,
    status: doc.status,
    end: end,
    settings: isObj(doc.settings) ? doc.settings : {},
    online: online
  }
}

// Applies `migrations` in order until `doc.version` reaches `target`.
// Returns { ok: true } or a failure; mutates `doc`.
export function migrateDocument(doc, migrations, target) {
  while (doc.version < target) {
    const migrate = migrations[doc.version]
    if (typeof migrate !== "function") return failure(SAVE_ERROR.UNSUPPORTED_VERSION, "version " + doc.version)
    const before = doc.version
    migrate(doc)
    if (!(Number.isInteger(doc.version) && doc.version > before))
      return failure(SAVE_ERROR.UNSUPPORTED_VERSION, "migration did not advance from " + before)
  }
  return { ok: true }
}

export function deserializeGame(text) {
  if (typeof text !== "string" || text.trim().length === 0) return failure(SAVE_ERROR.EMPTY)
  let doc
  try {
    doc = JSON.parse(text)
  } catch (e) {
    return failure(SAVE_ERROR.MALFORMED_JSON)
  }
  if (!isObj(doc) || doc.format !== SAVE_FORMAT) return failure(SAVE_ERROR.NOT_A_SAVE)
  if (!isInt(doc.version) || doc.version < 1) return failure(SAVE_ERROR.NOT_A_SAVE)
  if (doc.version > SAVE_VERSION) return failure(SAVE_ERROR.NEWER_VERSION, "version " + doc.version)
  const from = doc.version
  try {
    const migrated = migrateDocument(doc, MIGRATIONS, SAVE_VERSION)
    if (!migrated.ok) return migrated
    return { ok: true, state: buildState(doc), migratedFrom: from === SAVE_VERSION ? null : from }
  } catch (e) {
    if (e instanceof CorruptSave) return failure(SAVE_ERROR.CORRUPT, e.message)
    return failure(SAVE_ERROR.CORRUPT, String(e && e.message ? e.message : e))
  }
}
