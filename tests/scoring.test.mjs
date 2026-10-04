import { scoreWord, scoreMove, rackValue } from "../engine/scoring.mjs"
import { normalizeRules } from "../engine/rules.mjs"
import { previewMove } from "../engine/game.mjs"
import { letterValues, getTileset } from "../engine/tileset.mjs"
import { newGame, setRack, placeWord, placementsFor, wordDictionary } from "./lib/fixtures.mjs"

export const name = "Scoring"

const V = letterValues(getTileset("fr-classic"))

// Cells for `word` laid from (row, col); `isNew` is true unless the index is
// listed in `existing`. Lowercase letters are jokers.
function cells(word, row, col, dir, existing) {
  const out = []
  for (let k = 0; k < word.length; k++) {
    const ch = word.charAt(k)
    const joker = ch !== ch.toUpperCase()
    out.push({
      row: dir === "V" ? row + k : row,
      col: dir === "H" ? col + k : col,
      letter: ch.toUpperCase(),
      points: joker ? 0 : V[ch],
      isJoker: joker,
      isNew: !(existing && existing.indexOf(k) !== -1)
    })
  }
  return out
}

export function register(t) {
  const rules = normalizeRules({})

  t.test("normal word, no premium", function() {
    t.equal(scoreWord(cells("MOT", 9, 2, "H")).score, 4) // (9,2)-(9,4): no premiums
  })

  t.test("double letter", function() {
    // (7,3) is a double letter: A counts 2.
    const w = scoreWord(cells("MA", 7, 2, "H"))
    t.equal(w.score, 2 + 2)
    t.equal(w.breakdown[1].letterMultiplier, 2)
  })

  t.test("triple letter", function() {
    // (5,5) is a triple letter: Z counts 30.
    t.equal(scoreWord(cells("ZOO", 5, 5, "H")).score, 30 + 1 + 1)
  })

  t.test("double word", function() {
    // (4,4) double word: (2+1+1) × 2.
    t.equal(scoreWord(cells("MOT", 4, 4, "H")).score, 8)
  })

  t.test("triple word", function() {
    t.equal(scoreWord(cells("MOT", 0, 0, "H")).score, 12)
  })

  t.test("centre star doubles the word", function() {
    t.equal(scoreWord(cells("MOT", 7, 5, "H")).score, 8)
  })

  t.test("word multipliers stack (triple × triple)", function() {
    // Row 0, columns 0..7 covers two triple words and the double letter at (0,3).
    const w = scoreWord(cells("ABCDEFGH", 0, 0, "H"))
    const sum = V.A + V.B + V.C + V.D * 2 + V.E + V.F + V.G + V.H
    t.equal(w.wordMultiplier, 9)
    t.equal(w.score, sum * 9)
  })

  t.test("word multipliers stack (double × double)", function() {
    // Row 4: double words at columns 4 and 10.
    const w = scoreWord(cells("ABCDEFG", 4, 4, "H"))
    t.equal(w.wordMultiplier, 4)
    t.equal(w.score, (V.A + V.B + V.C + V.D + V.E + V.F + V.G) * 4)
  })

  t.test("premiums under existing tiles are not reused", function() {
    const w = scoreWord(cells("MOT", 0, 0, "H", [0]))
    t.equal(w.score, 4) // the triple word under M was spent earlier
  })

  t.test("a new tile on a premium counts in both of its words", function() {
    const across = cells("AS", 2, 5, "H", [0])  // S new at (2,6), a double letter
    const down = cells("OS", 1, 6, "V", [0])    // the same S
    const m = scoreMove([across, down], 1, rules)
    t.equal(m.words[0].score, 1 + 2)
    t.equal(m.words[1].score, 1 + 2)
    t.equal(m.total, 6)
  })

  t.test("joker scores zero, even on a letter premium", function() {
    const w = scoreWord(cells("zOO", 5, 5, "H"))
    t.equal(w.score, 0 + 1 + 1)
    const d = scoreWord(cells("mOT", 4, 4, "H"))
    t.equal(d.score, (0 + 1 + 1) * 2, "word premiums still apply")
  })

  t.test("seven tiles add the 50-point bonus", function() {
    const m = scoreMove([cells("ARTISTE", 7, 1, "H")], 7, rules)
    t.equal(m.bingo, true)
    t.equal(m.bonus, 50)
    t.equal(m.total, m.baseScore + 50)
    const six = scoreMove([cells("ARTIST", 7, 1, "H")], 6, rules)
    t.equal(six.bingo, false)
  })

  t.test("validator scores a first-move bingo", function() {
    const s = newGame()
    setRack(s, 0, "ARTISTE")
    const r = previewMove(s, 0, placementsFor(s, 0, "ARTISTE", 7, 1, "H"), wordDictionary())
    t.ok(r.valid, r.message)
    t.equal(r.baseScore, 16)
    t.equal(r.bonus, 50)
    t.equal(r.score, 66)
  })

  t.test("validator scores jokers and premiums together", function() {
    const s = newGame()
    setRack(s, 0, "MO?AEIU")
    const r = previewMove(s, 0, placementsFor(s, 0, "MOt", 7, 5, "H"), wordDictionary())
    t.ok(r.valid, r.message)
    t.equal(r.score, 6)
    t.equal(r.words[0].notation, "MO(T)")
  })

  t.test("validator: extending a word scores the whole word", function() {
    const s = newGame()
    placeWord(s, "MAISON", 7, 2, "H")
    setRack(s, 0, "SAEIRTU")
    const r = previewMove(s, 0, placementsFor(s, 0, "MAISONS", 7, 2, "H"), wordDictionary())
    t.ok(r.valid, r.message)
    t.deepEqual(r.formedWords, ["MAISONS"])
    t.equal(r.score, 8)
  })

  t.test("rack value for end-game adjustments", function() {
    t.equal(rackValue([{ points: 10, isJoker: false }, { points: 0, isJoker: true }, { points: 1, isJoker: false }]), 11)
  })
}
