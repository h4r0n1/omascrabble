// MoveEvaluator: turns a scored move into an equity — what the move is worth
// once what it leaves behind is counted.
//
//   equity = score
//          + leaveWeight   × leave(rack after the move)
//          − defenseWeight × danger(board after the move)
//          + premiumWeight × premium use bonus
//          + endgame corrections
//
// Leave values exist per tile language. French: the joker and S are worth
// keeping, E is the friendliest vowel, heavy consonants and duplicates hurt.
// English: close to the well-known single-tile leaves — X and Z keep well
// (many short words, high values), Q and V are a burden, U is a poor vowel.
// Either way a rack wants roughly two vowels for three consonants.

import { PREMIUM_LAYOUT, PREMIUM } from "../engine/board.mjs"

const N = 15
const BLANK = 26

// Value of keeping one copy of each letter, A..Z then the joker.
const SINGLE_FR = Float64Array.from([
  1.0,  // A
  -2.5, // B
  -0.5, // C
  0.0,  // D
  3.5,  // E
  -2.5, // F
  -2.5, // G
  -2.0, // H
  0.0,  // I
  -3.0, // J
  -6.0, // K
  0.8,  // L
  0.3,  // M
  1.2,  // N
  -1.0, // O
  -0.8, // P
  -6.0, // Q
  1.8,  // R
  8.0,  // S
  1.0,  // T
  -1.5, // U
  -4.5, // V
  -7.0, // W
  -1.0, // X
  -4.0, // Y
  -1.0, // Z
  24.0  // joker
])

// Cost of each extra copy of a letter.
const DUPLICATE_FR = Float64Array.from([
  -3.0, -4.0, -4.0, -3.5, -1.5, -4.0, -4.0, -4.0, -4.0, -6.0, -6.0, -2.5, -3.0,
  -2.5, -4.0, -3.5, -6.0, -2.5, -2.0, -2.5, -4.5, -5.0, -6.0, -6.0, -6.0, -6.0,
  -2.0
])

const SINGLE_EN = Float64Array.from([
  1.0,   // A
  -3.5,  // B
  -0.5,  // C
  0.0,   // D
  4.0,   // E
  -3.0,  // F
  -3.5,  // G
  0.5,   // H
  -1.5,  // I
  -2.5,  // J
  -3.5,  // K
  -1.5,  // L
  -0.5,  // M
  -0.5,  // N
  -2.5,  // O
  -1.5,  // P
  -11.5, // Q
  1.5,   // R
  7.5,   // S
  -1.0,  // T
  -4.5,  // U
  -6.5,  // V
  -4.0,  // W
  3.5,   // X
  -2.5,  // Y
  3.0,   // Z
  24.5   // blank
])

const DUPLICATE_EN = Float64Array.from([
  -3.0, -4.0, -4.0, -3.0, -2.0, -4.0, -4.0, -4.0, -4.5, -6.0, -6.0, -3.0, -3.0,
  -3.0, -3.5, -3.5, -6.0, -3.0, -3.0, -3.0, -5.0, -5.0, -5.0, -6.0, -5.0, -6.0,
  -3.0
])

const TABLES = {
  fr: { single: SINGLE_FR, duplicate: DUPLICATE_FR, vowels: "AEIOUY" },
  en: { single: SINGLE_EN, duplicate: DUPLICATE_EN, vowels: "AEIOU" }
}
for (const lang in TABLES) {
  const v = new Uint8Array(27)
  for (const ch of TABLES[lang].vowels) v[ch.charCodeAt(0) - 65] = 1
  TABLES[lang].vowel = v
}

// `language` is the tile set's language ("fr" by default).
export function leaveValue(counts, language) {
  const table = TABLES[language] || TABLES.fr
  const SINGLE = table.single
  const DUPLICATE = table.duplicate
  const VOWEL = table.vowel
  let value = 0
  let tiles = 0
  let vowels = 0
  for (let i = 0; i < 27; i++) {
    const c = counts[i]
    if (c <= 0) continue
    tiles += c
    value += SINGLE[i] + DUPLICATE[i] * (c - 1)
    if (i < 26 && VOWEL[i]) vowels += c
  }
  if (tiles === 0) return 0
  const consonants = tiles - vowels - counts[BLANK]
  const ideal = (tiles - counts[BLANK]) * 0.42
  const off = vowels - ideal
  value -= 1.6 * off * off
  if (consonants === 0 && tiles >= 3) value -= 3
  if (counts[16] > 0 && counts[20] === 0 && counts[BLANK] === 0) value -= 5 // Q without U
  return value
}

const HOT_TW = 7
const HOT_DW = 2.5
const HOT_LETTER = 1.2

// Danger created by a move: empty premium squares the new tiles make
// reachable for the opponent. `board` is the position BEFORE the move,
// `tiles` the new tiles [{ row, col }].
export function dangerOf(board, tiles) {
  let danger = 0
  const seen = new Set()
  const occupied = function(r, c) {
    if (r < 0 || c < 0 || r >= N || c >= N) return false
    if (board[r * N + c] >= 0) return true
    for (const t of tiles) if (t.row === r && t.col === c) return true
    return false
  }
  const wasAnchor = function(r, c) {
    if (r > 0 && board[(r - 1) * N + c] >= 0) return true
    if (r < N - 1 && board[(r + 1) * N + c] >= 0) return true
    if (c > 0 && board[r * N + c - 1] >= 0) return true
    if (c < N - 1 && board[r * N + c + 1] >= 0) return true
    return false
  }
  for (const t of tiles) {
    const around = [[t.row - 1, t.col], [t.row + 1, t.col], [t.row, t.col - 1], [t.row, t.col + 1]]
    for (const rc of around) {
      const r = rc[0], c = rc[1]
      if (r < 0 || c < 0 || r >= N || c >= N || occupied(r, c)) continue
      const key = r * N + c
      if (seen.has(key) || wasAnchor(r, c)) continue
      seen.add(key)
      const p = PREMIUM_LAYOUT[key]
      if (p === PREMIUM.TRIPLE_WORD) danger += HOT_TW
      else if (p === PREMIUM.DOUBLE_WORD) danger += HOT_DW
      else if (p === PREMIUM.TRIPLE_LETTER || p === PREMIUM.DOUBLE_LETTER) danger += HOT_LETTER
    }
    // A tile on an edge line opens the triple-word lane along it.
    if ((t.row === 0 || t.row === N - 1 || t.col === 0 || t.col === N - 1)) danger += 2
  }
  return danger
}

// Small bonus for spending premium squares with heavy tiles (the score
// already counts them; this nudges a profile with premium awareness to
// prefer the premium play over an equal-scoring flat one).
export function premiumUse(tiles, values) {
  let bonus = 0
  for (const t of tiles) {
    const p = PREMIUM_LAYOUT[t.row * N + t.col]
    if (p === PREMIUM.NONE || t.blank) continue
    const v = values[t.letter.charCodeAt(0) - 65]
    if (p === PREMIUM.TRIPLE_LETTER || p === PREMIUM.DOUBLE_LETTER) bonus += v >= 4 ? 1 : 0
    else bonus += 0.5
  }
  return bonus
}

export function rackValueOf(counts, values) {
  let sum = 0
  for (let i = 0; i < 26; i++) sum += counts[i] * values[i]
  return sum
}

// Endgame correction once the bag is empty: going out swings twice the
// opponent's rack; tiles stuck on our rack swing twice their value.
export function endgameAdjustment(leaveCounts, opponentRackValue, values) {
  let left = 0
  for (let i = 0; i < 27; i++) left += leaveCounts[i]
  if (left === 0) return 2 * opponentRackValue
  return -2 * rackValueOf(leaveCounts, values) - 4
}
