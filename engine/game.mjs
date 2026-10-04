// GameEngine: the authoritative game state machine.
//
// State is a plain JSON object (see createGame). applyAction(state, action,
// ctx) never mutates its input: it returns { ok, state, result, events } with
// a new state, or { ok: false, reason, message } and leaves the game as it
// was. Every rule lives here or in the modules it calls; the UI only renders
// state and submits actions, so the same engine serves local play, the AI,
// replays, tests and — later — a network peer.
//
// Actions:
//   { type: "play", player, placements: [{ tileId, row, col, jokerLetter? }] }
//   { type: "pass", player }
//   { type: "exchange", player, tileIds: [...] }
//   { type: "challenge", player }   contest the pending move (challenge rules)
//   { type: "accept", player }      accept a pending move that ends the game
//   { type: "resign", player }
//   { type: "timeout", player }     the player's clock reached zero
// Any action may carry `elapsedMs`, the time the acting player spent on it.
//
// ctx: { dictionary, now } — `now` (ms since epoch) defaults to Date.now().

import { getTileset, createTiles } from "./tileset.mjs"
import { createRng, cloneRng, nextInt, randomSeed } from "./rng.mjs"
import { Board, CELL_COUNT, cellIndex } from "./board.mjs"
import { normalizeRules, VALIDATION, CHALLENGE_PENALTY, TIMEOUT_POLICY, hasClock } from "./rules.mjs"
import { validateMove } from "./validator.mjs"
import { rackValue } from "./scoring.mjs"
import { REASON, messageFor } from "./reasons.mjs"

export const STATE_VERSION = 1

export const MODE = Object.freeze({
  HUMAN_VS_AI: "human_vs_ai",
  HUMAN_VS_HUMAN: "human_vs_human",
  PRACTICE: "practice",
  AI_VS_AI: "ai_vs_ai"          // demonstration / spectator: two AIs, nobody's stats
})

export const STATUS = Object.freeze({ ACTIVE: "active", ENDED: "ended" })

export const END_REASON = Object.freeze({
  OUT: "out",             // a player emptied their rack with the bag empty
  SCORELESS: "scoreless", // too many consecutive turns without a score
  TIMEOUT: "timeout",
  RESIGN: "resign"
})

function nowOf(ctx) {
  return ctx && Number.isFinite(ctx.now) ? ctx.now : Date.now()
}

function newGameId(rngSeed, now) {
  return "g" + now.toString(36) + "-" + (rngSeed >>> 0).toString(36)
}

// options: { mode, players: [{ name, kind: "human"|"ai", difficulty }],
//            rules, seed, dictionary: { id, name, version, official },
//            firstPlayer: index | "random", settings, now, gameId }
export function createGame(options) {
  const opts = options || {}
  const now = Number.isFinite(opts.now) ? opts.now : Date.now()
  const rules = normalizeRules(opts.rules)
  const tileset = getTileset(rules.tileset)
  const seed = opts.seed === undefined || opts.seed === null ? randomSeed() : opts.seed
  const rng = createRng(seed)
  const playerSpecs = Array.isArray(opts.players) && opts.players.length > 0 ? opts.players.slice(0, 4) : [{ name: "Joueur", kind: "human" }]
  const tiles = createTiles(tileset).map(function(t) { return { id: t.id, letter: t.letter, points: t.points, isJoker: t.isJoker } })
  const state = {
    version: STATE_VERSION,
    gameId: typeof opts.gameId === "string" && opts.gameId ? opts.gameId : newGameId(rng.seed, now),
    createdAt: new Date(now).toISOString(),
    updatedAt: new Date(now).toISOString(),
    mode: Object.keys(MODE).map(function(k) { return MODE[k] }).indexOf(opts.mode) !== -1 ? opts.mode : MODE.HUMAN_VS_AI,
    rules: rules,
    dictionary: Object.assign({ id: "", name: "", version: "", official: false }, opts.dictionary || {}),
    rng: rng,
    tiles: tiles,
    board: new Array(CELL_COUNT).fill(null),
    jokerLetters: {},
    bag: tiles.map(function(t) { return t.id }),
    players: playerSpecs.map(function(p, i) {
      return {
        name: typeof p.name === "string" && p.name ? p.name.slice(0, 40) : "Joueur " + (i + 1),
        kind: p.kind === "ai" ? "ai" : "human",
        difficulty: p.kind === "ai" && typeof p.difficulty === "string" ? p.difficulty : null,
        score: 0,
        rack: [],
        timeUsedMs: 0
      }
    }),
    current: 0,
    turn: 1,
    scorelessTurns: 0,
    moves: [],
    pending: null,
    status: STATUS.ACTIVE,
    end: null,
    settings: opts.settings && typeof opts.settings === "object" ? JSON.parse(JSON.stringify(opts.settings)) : {}
  }
  for (let p = 0; p < state.players.length; p++) drawTiles(state, p, rules.rackSize)
  if (opts.firstPlayer === "random") state.current = nextInt(state.rng, state.players.length)
  else if (Number.isInteger(opts.firstPlayer) && opts.firstPlayer >= 0 && opts.firstPlayer < state.players.length) state.current = opts.firstPlayer
  return state
}

// ------------------------------------------------------------------ queries

export function tileOf(state, id) {
  return state.tiles[id] || null
}

// The spec's full tile model, derived from the state (one source of truth):
// { id, letter, points, isJoker, jokerLetter, owner, position }.
export function tileView(state, id) {
  const t = tileOf(state, id)
  if (!t) return null
  const view = { id: t.id, letter: t.letter, points: t.points, isJoker: t.isJoker, jokerLetter: null, owner: null, position: null }
  const idx = state.board.indexOf(id)
  if (idx !== -1) {
    view.position = { zone: "board", row: Math.floor(idx / 15), col: idx % 15 }
    view.jokerLetter = t.isJoker ? (state.jokerLetters[id] || null) : null
    view.owner = boardOwner(state, id)
    return view
  }
  for (let p = 0; p < state.players.length; p++) {
    const r = state.players[p].rack.indexOf(id)
    if (r !== -1) {
      view.owner = p
      view.position = { zone: "rack", player: p, index: r }
      return view
    }
  }
  view.position = { zone: "bag" }
  return view
}

function boardOwner(state, id) {
  for (let i = state.moves.length - 1; i >= 0; i--) {
    const m = state.moves[i]
    if (m.type !== "play" || m.withdrawn) continue
    for (const pl of m.placements) if (pl.tileId === id) return m.player
  }
  return null
}

export function boardFromState(state) {
  const tiles = new Array(CELL_COUNT)
  for (let i = 0; i < CELL_COUNT; i++) {
    const id = state.board[i]
    if (id === null || id === undefined) { tiles[i] = null; continue }
    const t = state.tiles[id]
    tiles[i] = { id: t.id, letter: t.letter, points: t.points, isJoker: t.isJoker, jokerLetter: t.isJoker ? (state.jokerLetters[id] || null) : null }
  }
  return new Board(tiles)
}

export function rackTiles(state, player) {
  return state.players[player].rack.map(function(id) { return state.tiles[id] })
}

export function isFirstMove(state) {
  for (let i = 0; i < CELL_COUNT; i++) if (state.board[i] !== null) return false
  return true
}

export function canExchange(state) {
  return state.status === STATUS.ACTIVE && state.bag.length >= state.rules.exchangeMinBag
}

// What the player to move may do right now.
export function legalActions(state, player) {
  const active = state.status === STATUS.ACTIVE
  const myTurn = active && player === state.current
  const pending = state.pending
  const blocking = !!(pending && pending.endsGame)
  return {
    play: myTurn && !blocking,
    pass: myTurn && !blocking,
    exchange: myTurn && !blocking && canExchange(state),
    challenge: myTurn && !!pending && pending.player !== player,
    accept: myTurn && blocking && pending.player !== player,
    resign: active && state.players[player] !== undefined
  }
}

// Validates a placement without changing the game: the move preview, and
// what the UI uses to explain a refusal before it happens.
export function previewMove(state, player, placements, dictionary, options) {
  const checkWords = options && options.checkWords !== undefined
    ? options.checkWords
    : state.rules.validation === VALIDATION.IMMEDIATE
  return validateMove({
    board: boardFromState(state),
    rack: rackTiles(state, player),
    placements: placements,
    dictionary: dictionary,
    rules: state.rules,
    checkWords: checkWords
  })
}

// Tiles the given player cannot see: the bag plus every other rack. Bag order
// is never exposed — this is what a fair AI is allowed to know.
export function unseenCounts(state, player) {
  const counts = {}
  const add = function(id) {
    const l = state.tiles[id].letter
    counts[l] = (counts[l] || 0) + 1
  }
  state.bag.forEach(add)
  for (let p = 0; p < state.players.length; p++) if (p !== player) state.players[p].rack.forEach(add)
  return counts
}

export function timeRemainingMs(state, player) {
  if (!hasClock(state.rules)) return Infinity
  return state.rules.time.totalMs - state.players[player].timeUsedMs
}

// Everything the player may legitimately know, in a compact form for the AI
// worker: no bag order, no opponent rack.
export function publicView(state, player) {
  const board = boardFromState(state)
  const cells = new Array(CELL_COUNT)
  for (let i = 0; i < CELL_COUNT; i++) {
    const t = board.tiles[i]
    cells[i] = t ? { letter: t.isJoker ? t.jokerLetter : t.letter, isJoker: t.isJoker, points: t.isJoker ? 0 : t.points } : null
  }
  const pending = state.pending ? state.moves[state.pending.moveIndex] : null
  return {
    me: player,
    board: cells,
    rack: rackTiles(state, player).map(function(t) { return { id: t.id, letter: t.letter, points: t.points, isJoker: t.isJoker } }),
    bagCount: state.bag.length,
    unseen: unseenCounts(state, player),
    scores: state.players.map(function(p) { return p.score }),
    rackCounts: state.players.map(function(p) { return p.rack.length }),
    rules: state.rules,
    turn: state.turn,
    scorelessTurns: state.scorelessTurns,
    playerCount: state.players.length,
    isFirstMove: isFirstMove(state),
    timeRemainingMs: hasClock(state.rules) ? timeRemainingMs(state, player) : null,
    pending: pending && state.pending.player !== player
      ? { player: state.pending.player, words: pending.words.map(function(w) { return w.word }), endsGame: !!state.pending.endsGame, score: pending.score }
      : null
  }
}

// ------------------------------------------------------------------ actions

function cloneState(state) {
  return {
    version: state.version,
    gameId: state.gameId,
    createdAt: state.createdAt,
    updatedAt: state.updatedAt,
    mode: state.mode,
    rules: state.rules,
    dictionary: state.dictionary,
    rng: cloneRng(state.rng),
    tiles: state.tiles,
    board: state.board.slice(),
    jokerLetters: Object.assign({}, state.jokerLetters),
    bag: state.bag.slice(),
    players: state.players.map(function(p) { return Object.assign({}, p, { rack: p.rack.slice() }) }),
    current: state.current,
    turn: state.turn,
    scorelessTurns: state.scorelessTurns,
    moves: state.moves.slice(),
    pending: state.pending ? Object.assign({}, state.pending) : null,
    status: state.status,
    end: state.end,
    settings: state.settings
  }
}

function drawTiles(state, player, count) {
  const drawn = []
  const rack = state.players[player].rack
  for (let i = 0; i < count && state.bag.length > 0; i++) {
    const idx = nextInt(state.rng, state.bag.length)
    const id = state.bag.splice(idx, 1)[0]
    rack.push(id)
    drawn.push(id)
  }
  return drawn
}

function fail(reason, extra) {
  return Object.assign({ ok: false, reason: reason, message: messageFor(reason, extra && extra.detail) }, extra || {})
}

function nextPlayer(state, p) {
  return (p + 1) % state.players.length
}

function scorelessLimit(state) {
  return state.rules.endGame.scorelessRounds * state.players.length
}

function endTurn(state, events) {
  state.current = nextPlayer(state, state.current)
  state.turn++
  events.push({ type: "turn", player: state.current })
}

function recordMove(state, move, ctx) {
  move.index = state.moves.length
  move.turn = state.turn
  move.at = new Date(nowOf(ctx)).toISOString()
  state.moves.push(move)
  return move
}

// Accepting the pending move: it simply stands. Returns true if that ends
// the game (the move emptied the last rack).
function settlePending(state, events, ctx) {
  if (!state.pending) return false
  const pending = state.pending
  state.pending = null
  const m = state.moves[pending.moveIndex]
  state.moves[pending.moveIndex] = Object.assign({}, m, { provisional: false })
  events.push({ type: "move_accepted", moveIndex: pending.moveIndex })
  if (pending.endsGame) {
    finalize(state, END_REASON.OUT, pending.player, events, ctx)
    return true
  }
  return false
}

function finalize(state, reason, actor, events, ctx) {
  const n = state.players.length
  const remaining = state.players.map(function(p) { return rackValue(p.rack.map(function(id) { return state.tiles[id] })) })
  const adjustments = new Array(n).fill(0)
  const eg = state.rules.endGame
  if (reason === END_REASON.OUT) {
    let others = 0
    for (let i = 0; i < n; i++) {
      if (i === actor) continue
      others += remaining[i]
      if (eg.remainingPenalty) adjustments[i] -= remaining[i]
    }
    if (eg.outBonus) adjustments[actor] += others
  } else if (reason === END_REASON.SCORELESS || reason === END_REASON.TIMEOUT) {
    if (eg.remainingPenalty) for (let i = 0; i < n; i++) adjustments[i] -= remaining[i]
  }
  const timePenalties = new Array(n).fill(0)
  if (hasClock(state.rules) && state.rules.time.onTimeout === TIMEOUT_POLICY.PENALTY) {
    for (let i = 0; i < n; i++) {
      const over = state.players[i].timeUsedMs - state.rules.time.totalMs
      if (over > 0) timePenalties[i] = Math.ceil(over / 60000) * state.rules.time.overtimePenaltyPerMinute
      adjustments[i] -= timePenalties[i]
    }
  }
  const finalScores = state.players.map(function(p, i) { return p.score + adjustments[i] })
  let winner = null
  if (n > 1) {
    // Resigning or running out of time loses, whatever the scores.
    if (reason === END_REASON.RESIGN || reason === END_REASON.TIMEOUT) {
      let best = -Infinity
      for (let i = 0; i < n; i++) {
        if (i === actor) continue
        if (finalScores[i] > best) { best = finalScores[i]; winner = i }
      }
    } else {
      let best = -Infinity, count = 0
      for (let i = 0; i < n; i++) {
        if (finalScores[i] > best) { best = finalScores[i]; winner = i; count = 1 }
        else if (finalScores[i] === best) count++
      }
      if (count > 1) winner = null
    }
  }
  state.status = STATUS.ENDED
  state.pending = null
  state.end = {
    reason: reason,
    actor: actor,
    remaining: remaining,
    adjustments: adjustments,
    timePenalties: timePenalties,
    finalScores: finalScores,
    winner: winner,
    endedAt: new Date(nowOf(ctx)).toISOString()
  }
  events.push({ type: "game_over", reason: reason, winner: winner, finalScores: finalScores })
}

function checkScoreless(state, events, ctx) {
  if (state.status === STATUS.ACTIVE && state.scorelessTurns >= scorelessLimit(state)) {
    finalize(state, END_REASON.SCORELESS, state.current, events, ctx)
    return true
  }
  return false
}

function doPlay(state, p, action, ctx, events) {
  if (state.pending && state.pending.endsGame) return fail(REASON.CHALLENGE_PENDING)
  const challengeRules = state.rules.validation === VALIDATION.CHALLENGE
  const validation = validateMove({
    board: boardFromState(state),
    rack: rackTiles(state, p),
    placements: action.placements,
    dictionary: ctx.dictionary,
    rules: state.rules,
    checkWords: !challengeRules
  })
  if (!validation.valid) return fail(validation.reason, { message: validation.message, result: validation })

  if (state.pending) settlePending(state, events, ctx)

  const player = state.players[p]
  const rackBefore = player.rack.slice()
  for (const pt of validation.placedTiles) {
    state.board[cellIndex(pt.row, pt.col)] = pt.tileId
    if (pt.isJoker) state.jokerLetters[pt.tileId] = pt.letter
    player.rack.splice(player.rack.indexOf(pt.tileId), 1)
  }
  player.score += validation.score
  const drawn = drawTiles(state, p, state.rules.rackSize - player.rack.length)
  const prevScoreless = state.scorelessTurns
  state.scorelessTurns = validation.score > 0 ? 0 : state.scorelessTurns + 1
  const move = recordMove(state, {
    type: "play",
    player: p,
    placements: validation.placedTiles.map(function(t) { return { tileId: t.tileId, row: t.row, col: t.col, letter: t.letter, isJoker: t.isJoker } }),
    words: validation.words.map(function(w) {
      return { word: w.word, notation: w.notation, score: w.score, isMain: w.isMain, wordMultiplier: w.wordMultiplier, cells: w.cells }
    }),
    mainWord: validation.mainWord,
    position: validation.position,
    direction: validation.direction,
    score: validation.score,
    bingo: validation.bingo,
    bonus: validation.bonus,
    rackBefore: rackBefore,
    drawn: drawn,
    elapsedMs: Number.isFinite(action.elapsedMs) ? Math.round(action.elapsedMs) : 0,
    provisional: challengeRules,
    withdrawn: false
  }, ctx)
  events.push({ type: "play", player: p, moveIndex: move.index, score: validation.score, bingo: validation.bingo, cells: move.placements })
  if (drawn.length) events.push({ type: "draw", player: p, count: drawn.length })

  const wentOut = player.rack.length === 0 && state.bag.length === 0
  if (challengeRules) {
    state.pending = { moveIndex: move.index, player: p, drawn: drawn, prevScoreless: prevScoreless, endsGame: wentOut }
    endTurn(state, events)
    return { ok: true, state: state, result: validation, events: events }
  }
  if (wentOut) {
    finalize(state, END_REASON.OUT, p, events, ctx)
    return { ok: true, state: state, result: validation, events: events }
  }
  endTurn(state, events)
  checkScoreless(state, events, ctx)
  return { ok: true, state: state, result: validation, events: events }
}

function doPass(state, p, action, ctx, events) {
  if (state.pending && state.pending.endsGame) return fail(REASON.CHALLENGE_PENDING)
  if (state.pending) settlePending(state, events, ctx)
  recordMove(state, { type: "pass", player: p, score: 0, elapsedMs: Number.isFinite(action.elapsedMs) ? Math.round(action.elapsedMs) : 0 }, ctx)
  state.scorelessTurns++
  events.push({ type: "pass", player: p })
  endTurn(state, events)
  checkScoreless(state, events, ctx)
  return { ok: true, state: state, result: null, events: events }
}

function doExchange(state, p, action, ctx, events) {
  if (state.pending && state.pending.endsGame) return fail(REASON.CHALLENGE_PENDING)
  if (state.bag.length < state.rules.exchangeMinBag) return fail(REASON.BAG_TOO_SMALL, { detail: state.rules.exchangeMinBag })
  const ids = action.tileIds
  if (!Array.isArray(ids) || ids.length === 0) return fail(REASON.NOTHING_TO_EXCHANGE)
  const player = state.players[p]
  const seen = new Set()
  for (const id of ids) {
    if (!Number.isInteger(id)) return fail(REASON.BAD_PLACEMENT)
    if (seen.has(id)) return fail(REASON.DUPLICATE_TILE)
    if (player.rack.indexOf(id) === -1) return fail(REASON.TILE_NOT_OWNED)
    seen.add(id)
  }
  if (state.pending) settlePending(state, events, ctx)
  const rackBefore = player.rack.slice()
  for (const id of ids) player.rack.splice(player.rack.indexOf(id), 1)
  // Draw first, then put the returned tiles back: a player can never draw
  // back a tile they just exchanged.
  const drawn = drawTiles(state, p, ids.length)
  for (const id of ids) state.bag.push(id)
  recordMove(state, {
    type: "exchange", player: p, score: 0, count: ids.length, tileIds: ids.slice(), drawn: drawn, rackBefore: rackBefore,
    elapsedMs: Number.isFinite(action.elapsedMs) ? Math.round(action.elapsedMs) : 0
  }, ctx)
  state.scorelessTurns++
  events.push({ type: "exchange", player: p, count: ids.length })
  endTurn(state, events)
  checkScoreless(state, events, ctx)
  return { ok: true, state: state, result: null, events: events }
}

function doChallenge(state, p, action, ctx, events) {
  const pending = state.pending
  if (!pending || pending.player === p) return fail(REASON.NO_PENDING_MOVE)
  const dictionary = ctx.dictionary
  if (!dictionary || typeof dictionary.isValid !== "function") return fail(REASON.DICTIONARY_UNAVAILABLE)
  const target = state.moves[pending.moveIndex]
  const checked = target.words.map(function(w) {
    return { word: w.word, valid: w.word.length >= state.rules.minWordLength && dictionary.isValid(w.word) === true }
  })
  const invalidWords = checked.filter(function(c) { return !c.valid }).map(function(c) { return c.word })
  const success = invalidWords.length > 0
  state.pending = null
  let penalty = null

  if (success) {
    // Withdraw the move: tiles back to the rack in their original order,
    // replacement tiles back to the bag, points taken back.
    const challenged = state.players[pending.player]
    for (const id of pending.drawn) {
      const i = challenged.rack.indexOf(id)
      if (i !== -1) challenged.rack.splice(i, 1)
      state.bag.push(id)
    }
    for (const pl of target.placements) {
      state.board[cellIndex(pl.row, pl.col)] = null
      delete state.jokerLetters[pl.tileId]
    }
    challenged.rack = target.rackBefore.slice()
    challenged.score -= target.score
    state.scorelessTurns = pending.prevScoreless + 1
    state.moves[pending.moveIndex] = Object.assign({}, target, { provisional: false, withdrawn: true })
    events.push({ type: "move_withdrawn", moveIndex: pending.moveIndex, player: pending.player, cells: target.placements })
  } else {
    state.moves[pending.moveIndex] = Object.assign({}, target, { provisional: false })
    const rule = state.rules.challenge
    if (rule.penalty === CHALLENGE_PENALTY.POINTS) {
      penalty = { type: "points", points: rule.penaltyPoints }
      state.players[p].score -= rule.penaltyPoints
    } else if (rule.penalty === CHALLENGE_PENALTY.LOSE_TURN) {
      penalty = { type: "lose_turn" }
    }
  }

  recordMove(state, {
    type: "challenge", player: p, target: pending.moveIndex, success: success,
    checked: checked, invalidWords: invalidWords, penalty: penalty, score: penalty && penalty.type === "points" ? -penalty.points : 0,
    elapsedMs: Number.isFinite(action.elapsedMs) ? Math.round(action.elapsedMs) : 0
  }, ctx)
  events.push({ type: "challenge", player: p, success: success, invalidWords: invalidWords, checked: checked, penalty: penalty })

  if (!success && pending.endsGame) {
    finalize(state, END_REASON.OUT, pending.player, events, ctx)
    return { ok: true, state: state, result: { success: success, checked: checked, invalidWords: invalidWords, penalty: penalty }, events: events }
  }
  if (!success && penalty && penalty.type === "lose_turn") {
    state.scorelessTurns++
    endTurn(state, events)
    checkScoreless(state, events, ctx)
  }
  // A successful challenge leaves the turn with the challenger, who now plays.
  return { ok: true, state: state, result: { success: success, checked: checked, invalidWords: invalidWords, penalty: penalty }, events: events }
}

function doAccept(state, p, action, ctx, events) {
  if (!state.pending || state.pending.player === p) return fail(REASON.NO_PENDING_MOVE)
  settlePending(state, events, ctx)
  return { ok: true, state: state, result: null, events: events }
}

function doResign(state, p, action, ctx, events) {
  recordMove(state, { type: "resign", player: p, score: 0, elapsedMs: 0 }, ctx)
  events.push({ type: "resign", player: p })
  finalize(state, END_REASON.RESIGN, p, events, ctx)
  return { ok: true, state: state, result: null, events: events }
}

function doTimeout(state, p, action, ctx, events) {
  if (!hasClock(state.rules) || state.players[p].timeUsedMs < state.rules.time.totalMs) return fail(REASON.TIME_NOT_EXPIRED)
  if (state.rules.time.onTimeout !== TIMEOUT_POLICY.END_GAME) return fail(REASON.TIME_NOT_EXPIRED)
  recordMove(state, { type: "timeout", player: p, score: 0, elapsedMs: 0 }, ctx)
  events.push({ type: "timeout", player: p })
  finalize(state, END_REASON.TIMEOUT, p, events, ctx)
  return { ok: true, state: state, result: null, events: events }
}

const HANDLERS = {
  play: doPlay,
  pass: doPass,
  exchange: doExchange,
  challenge: doChallenge,
  accept: doAccept,
  resign: doResign,
  timeout: doTimeout
}

export function applyAction(state, action, ctx) {
  const context = ctx || {}
  if (!action || typeof action !== "object" || !HANDLERS[action.type]) return fail(REASON.UNKNOWN_ACTION)
  if (state.status !== STATUS.ACTIVE) return fail(REASON.GAME_OVER)
  const p = action.player
  if (!Number.isInteger(p) || p < 0 || p >= state.players.length) return fail(REASON.BAD_PLAYER)
  const outOfTurn = action.type === "resign" || action.type === "timeout"
  if (!outOfTurn && p !== state.current) return fail(REASON.NOT_YOUR_TURN)

  const next = cloneState(state)
  if (Number.isFinite(action.elapsedMs) && action.elapsedMs > 0 && (p === state.current || action.type === "timeout"))
    next.players[p].timeUsedMs += Math.round(action.elapsedMs)
  const events = []
  const outcome = HANDLERS[action.type](next, p, action, context, events)
  if (!outcome.ok) return outcome
  next.updatedAt = new Date(nowOf(context)).toISOString()
  return outcome
}

// Adds time to the player on move without any other change (used when the
// controller persists a running clock).
export function withElapsed(state, player, elapsedMs) {
  if (!(elapsedMs > 0) || state.status !== STATUS.ACTIVE) return state
  const next = cloneState(state)
  next.players[player].timeUsedMs += Math.round(elapsedMs)
  return next
}

export function isGameOver(state) {
  return state.status === STATUS.ENDED
}
