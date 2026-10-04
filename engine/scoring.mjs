// The scoring engine. Pure functions over word cells; no board or UI state.
//
// A word cell is { row, col, letter, points, isJoker, isNew }. Rules applied:
//   - a joker scores 0 wherever it lies;
//   - letter premiums multiply only newly placed tiles;
//   - word premiums under newly placed tiles multiply the whole word, and
//     several of them multiply together (2 × 3 = ×6, 3 × 3 = ×9);
//   - every word a move forms is scored, so a new tile shared by two words
//     (with its premium) counts in both;
//   - placing `bingoTiles` tiles in one move adds `bingoBonus`.

import { premiumAt, letterMultiplier, wordMultiplier, PREMIUM } from "./board.mjs"

export function scoreWord(cells) {
  let letterSum = 0
  let multiplier = 1
  const breakdown = []
  for (const cell of cells) {
    const premium = cell.isNew ? premiumAt(cell.row, cell.col) : PREMIUM.NONE
    const base = cell.isJoker ? 0 : cell.points
    const lm = letterMultiplier(premium)
    const value = base * lm
    letterSum += value
    multiplier *= wordMultiplier(premium)
    breakdown.push({
      row: cell.row, col: cell.col, letter: cell.letter, isJoker: !!cell.isJoker, isNew: !!cell.isNew,
      base: base, letterMultiplier: lm, value: value, premium: premium
    })
  }
  return { score: letterSum * multiplier, letterSum: letterSum, wordMultiplier: multiplier, breakdown: breakdown }
}

// `words` is an array of arrays of cells; returns the move's total with a
// per-word breakdown, in the order given (main word first by convention).
export function scoreMove(words, placedCount, rules) {
  const scored = words.map(scoreWord)
  let base = 0
  for (const w of scored) base += w.score
  const bingo = placedCount >= rules.bingoTiles
  const bonus = bingo ? rules.bingoBonus : 0
  return { words: scored, baseScore: base, bingo: bingo, bonus: bonus, total: base + bonus }
}

// Sum of the face values left on a rack (jokers count 0), for the end-game
// adjustment.
export function rackValue(tiles) {
  let sum = 0
  for (const t of tiles) sum += t && !t.isJoker ? t.points : 0
  return sum
}
