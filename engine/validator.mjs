// MoveValidator: decides whether a proposed placement is a legal move and
// what it scores. It re-derives everything from the board, the player's rack
// and the placements themselves — nothing from the UI is trusted.
//
// Input:
//   board       Board before the move
//   rack        the player's rack tiles ({ id, letter, points, isJoker })
//   placements  [{ tileId, row, col, jokerLetter? }]
//   dictionary  a DictionaryProvider (required when checkWords is true)
//   rules       normalized rules
//   checkWords  false for provisional moves under challenge rules
//
// Output (always the same shape):
//   { valid, reason, message, formedWords[], invalidWords[], words[], score,
//     baseScore, bingo, bonus, placedTiles[], direction, position, mainWord }

import { Board, inBounds, cellIndex, effectiveLetter, CENTER_ROW, CENTER_COL } from "./board.mjs"
import { scoreMove } from "./scoring.mjs"
import { REASON, messageFor } from "./reasons.mjs"
import { positionLabel, wordNotation } from "./notation.mjs"

const LETTER_RE = /^[A-Z]$/

function result(reason, extra) {
  const r = {
    valid: reason === REASON.OK,
    reason: reason,
    message: "",
    formedWords: [],
    invalidWords: [],
    words: [],
    score: 0,
    baseScore: 0,
    bingo: false,
    bonus: 0,
    placedTiles: [],
    direction: "",
    position: "",
    mainWord: "",
    cell: null
  }
  if (extra) for (const k in extra) r[k] = extra[k]
  r.message = messageFor(reason, reason === REASON.INVALID_WORD || reason === REASON.INVALID_CROSS_WORD ? r.invalidWords : undefined)
  return r
}

// The maximal run of occupied cells through (row, col) along `dir`.
function runThrough(board, row, col, dir, newCells) {
  const dr = dir === "V" ? 1 : 0
  const dc = dir === "H" ? 1 : 0
  let r = row, c = col
  while (board.isOccupied(r - dr, c - dc)) { r -= dr; c -= dc }
  const cells = []
  while (board.isOccupied(r, c)) {
    const tile = board.get(r, c)
    cells.push({
      row: r, col: c, tileId: tile.id,
      letter: effectiveLetter(tile), points: tile.points, isJoker: tile.isJoker,
      isNew: newCells.has(cellIndex(r, c))
    })
    r += dr; c += dc
  }
  return cells
}

export function validateMove(input) {
  const board = input.board
  const rack = Array.isArray(input.rack) ? input.rack : []
  const placements = input.placements
  const rules = input.rules
  const checkWords = input.checkWords !== false

  if (!Array.isArray(placements) || placements.length === 0) return result(REASON.NO_TILES)
  if (placements.length > rules.rackSize || placements.length > rack.length) return result(REASON.TOO_MANY_TILES)

  const rackById = new Map()
  for (const t of rack) rackById.set(t.id, t)
  const seenIds = new Set()
  const seenCells = new Set()
  const placed = []
  for (const p of placements) {
    if (!p || typeof p !== "object" || !Number.isInteger(p.tileId) || !Number.isInteger(p.row) || !Number.isInteger(p.col))
      return result(REASON.BAD_PLACEMENT)
    const cell = { row: p.row, col: p.col }
    if (!inBounds(p.row, p.col)) return result(REASON.OUT_OF_BOUNDS, { cell: cell })
    if (seenIds.has(p.tileId)) return result(REASON.DUPLICATE_TILE, { cell: cell })
    const key = cellIndex(p.row, p.col)
    if (seenCells.has(key)) return result(REASON.DUPLICATE_POSITION, { cell: cell })
    if (board.isOccupied(p.row, p.col)) return result(REASON.CELL_OCCUPIED, { cell: cell })
    const tile = rackById.get(p.tileId)
    if (!tile) return result(REASON.TILE_NOT_OWNED, { cell: cell })
    let jokerLetter = null
    const hasJokerLetter = p.jokerLetter !== undefined && p.jokerLetter !== null && p.jokerLetter !== ""
    if (tile.isJoker) {
      if (!hasJokerLetter) return result(REASON.JOKER_LETTER_MISSING, { cell: cell })
      if (typeof p.jokerLetter !== "string" || !LETTER_RE.test(p.jokerLetter)) return result(REASON.JOKER_LETTER_INVALID, { cell: cell })
      jokerLetter = p.jokerLetter
    } else if (hasJokerLetter) {
      return result(REASON.NOT_A_JOKER, { cell: cell })
    }
    seenIds.add(p.tileId)
    seenCells.add(key)
    placed.push({
      row: p.row, col: p.col,
      tile: { id: tile.id, letter: tile.letter, points: tile.points, isJoker: tile.isJoker, jokerLetter: jokerLetter }
    })
  }

  const sameRow = placed.every(function(p) { return p.row === placed[0].row })
  const sameCol = placed.every(function(p) { return p.col === placed[0].col })
  if (!sameRow && !sameCol) return result(REASON.NOT_IN_LINE)

  const after = board.clone()
  for (const p of placed) after.set(p.row, p.col, p.tile)

  let direction
  if (placed.length > 1) {
    direction = sameRow ? "H" : "V"
  } else {
    const p = placed[0]
    const horizontal = after.isOccupied(p.row, p.col - 1) || after.isOccupied(p.row, p.col + 1)
    const vertical = after.isOccupied(p.row - 1, p.col) || after.isOccupied(p.row + 1, p.col)
    direction = horizontal || !vertical ? "H" : "V"
  }

  // Every cell between the first and last new tile must be filled, by a new
  // tile or one already on the board.
  if (direction === "H") {
    const row = placed[0].row
    let min = 15, max = -1
    for (const p of placed) { min = Math.min(min, p.col); max = Math.max(max, p.col) }
    for (let c = min; c <= max; c++) if (after.isEmpty(row, c)) return result(REASON.GAP_IN_WORD, { cell: { row: row, col: c } })
  } else {
    const col = placed[0].col
    let min = 15, max = -1
    for (const p of placed) { min = Math.min(min, p.row); max = Math.max(max, p.row) }
    for (let r = min; r <= max; r++) if (after.isEmpty(r, col)) return result(REASON.GAP_IN_WORD, { cell: { row: r, col: col } })
  }

  const newCells = seenCells
  if (board.isEmptyBoard()) {
    if (!newCells.has(cellIndex(CENTER_ROW, CENTER_COL))) return result(REASON.FIRST_MOVE_NOT_ON_CENTER)
  } else {
    let connected = false
    for (const p of placed) if (board.hasNeighbor(p.row, p.col)) { connected = true; break }
    if (!connected) return result(REASON.NOT_CONNECTED)
  }

  const words = []
  const main = runThrough(after, placed[0].row, placed[0].col, direction, newCells)
  if (main.length >= 2) words.push({ cells: main, isMain: true })
  const cross = direction === "H" ? "V" : "H"
  for (const p of placed) {
    const run = runThrough(after, p.row, p.col, cross, newCells)
    if (run.length >= 2) words.push({ cells: run, isMain: false })
  }
  if (words.length === 0) return result(REASON.SINGLE_LETTER)

  const scored = scoreMove(words.map(function(w) { return w.cells }), placed.length, rules)
  const wordDetails = words.map(function(w, i) {
    const text = w.cells.map(function(c) { return c.letter }).join("")
    const s = scored.words[i]
    return {
      word: text,
      notation: wordNotation(w.cells),
      isMain: w.isMain,
      score: s.score,
      letterSum: s.letterSum,
      wordMultiplier: s.wordMultiplier,
      breakdown: s.breakdown,
      cells: w.cells.map(function(c) { return { row: c.row, col: c.col, isNew: c.isNew } }),
      valid: null
    }
  })
  const formedWords = wordDetails.map(function(w) { return w.word })
  const start = main.length >= 2 ? main[0] : placed[0]
  const extra = {
    formedWords: formedWords,
    words: wordDetails,
    score: scored.total,
    baseScore: scored.baseScore,
    bingo: scored.bingo,
    bonus: scored.bonus,
    placedTiles: placed.map(function(p) {
      return { tileId: p.tile.id, row: p.row, col: p.col, letter: effectiveLetter(p.tile), isJoker: p.tile.isJoker, points: p.tile.points }
    }),
    direction: direction,
    position: positionLabel(direction, start.row, start.col),
    mainWord: wordDetails[0].word
  }

  if (!checkWords) return result(REASON.OK, extra)

  const dictionary = input.dictionary
  if (!dictionary || typeof dictionary.isValid !== "function") return result(REASON.DICTIONARY_UNAVAILABLE, extra)
  const invalid = []
  let mainInvalid = false
  for (const w of wordDetails) {
    w.valid = w.word.length >= rules.minWordLength && dictionary.isValid(w.word) === true
    if (!w.valid) {
      if (invalid.indexOf(w.word) === -1) invalid.push(w.word)
      if (w.isMain) mainInvalid = true
    }
  }
  if (invalid.length > 0) {
    extra.invalidWords = invalid
    return result(mainInvalid ? REASON.INVALID_WORD : REASON.INVALID_CROSS_WORD, extra)
  }
  return result(REASON.OK, extra)
}

export { Board }
