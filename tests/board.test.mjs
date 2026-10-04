import { Board, PREMIUM, PREMIUM_LAYOUT, premiumAt, BOARD_SIZE, CELL_COUNT, inBounds, CENTER_ROW, CENTER_COL } from "../engine/board.mjs"
import { previewMove, applyAction } from "../engine/game.mjs"
import { REASON } from "../engine/reasons.mjs"
import { newGame, setRack, placeWord, placementsFor, wordDictionary } from "./lib/fixtures.mjs"

export const name = "Board"

export function register(t) {
  t.test("layout has the classic premium counts", function() {
    const count = {}
    for (const p of PREMIUM_LAYOUT) count[p] = (count[p] || 0) + 1
    t.equal(PREMIUM_LAYOUT.length, 225)
    t.equal(count[PREMIUM.TRIPLE_WORD], 8)
    t.equal(count[PREMIUM.DOUBLE_WORD], 16)
    t.equal(count[PREMIUM.CENTER], 1)
    t.equal(count[PREMIUM.TRIPLE_LETTER], 12)
    t.equal(count[PREMIUM.DOUBLE_LETTER], 24)
  })

  t.test("known premium squares", function() {
    t.equal(premiumAt(0, 0), PREMIUM.TRIPLE_WORD)
    t.equal(premiumAt(0, 7), PREMIUM.TRIPLE_WORD)
    t.equal(premiumAt(14, 14), PREMIUM.TRIPLE_WORD)
    t.equal(premiumAt(1, 1), PREMIUM.DOUBLE_WORD)
    t.equal(premiumAt(4, 10), PREMIUM.DOUBLE_WORD)
    t.equal(premiumAt(1, 5), PREMIUM.TRIPLE_LETTER)
    t.equal(premiumAt(9, 9), PREMIUM.TRIPLE_LETTER)
    t.equal(premiumAt(0, 3), PREMIUM.DOUBLE_LETTER)
    t.equal(premiumAt(7, 3), PREMIUM.DOUBLE_LETTER)
    t.equal(premiumAt(6, 6), PREMIUM.DOUBLE_LETTER)
    t.equal(premiumAt(7, 7), PREMIUM.CENTER)
    t.equal(premiumAt(7, 8), PREMIUM.NONE)
    t.equal(premiumAt(15, 0), PREMIUM.NONE)
  })

  t.test("layout is symmetric", function() {
    for (let r = 0; r < 15; r++) for (let c = 0; c < 15; c++) {
      t.equal(premiumAt(r, c), premiumAt(c, r))
      t.equal(premiumAt(r, c), premiumAt(14 - r, c))
      t.equal(premiumAt(r, c), premiumAt(r, 14 - c))
    }
  })

  t.test("matrix cells know row, column, premium and tile", function() {
    const b = new Board()
    const m = b.toMatrix()
    t.equal(m.length, BOARD_SIZE)
    t.equal(m[3].length, BOARD_SIZE)
    t.deepEqual(m[7][7], { row: 7, column: 7, premiumType: PREMIUM.CENTER, tile: null })
    b.set(2, 3, { id: 0, letter: "A", points: 1, isJoker: false, jokerLetter: null })
    t.equal(b.toMatrix()[2][3].tile.letter, "A")
    t.ok(b.isOccupied(2, 3))
    t.ok(b.hasNeighbor(2, 4))
    t.ok(!b.hasNeighbor(5, 5))
    t.equal(CELL_COUNT, 225)
    t.ok(inBounds(14, 14) && !inBounds(15, 0) && !inBounds(-1, 3) && !inBounds(1.5, 2))
  })

  t.test("first move must cover the centre star", function() {
    const s = newGame()
    setRack(s, 0, "MAISONS")
    const off = previewMove(s, 0, placementsFor(s, 0, "MAISON", 6, 2, "H"), wordDictionary())
    t.equal(off.reason, REASON.FIRST_MOVE_NOT_ON_CENTER)
    const on = previewMove(s, 0, placementsFor(s, 0, "MAISON", 7, 2, "H"), wordDictionary())
    t.ok(on.valid, on.message)
    t.equal(on.position, "H3")
    t.equal(CENTER_ROW, 7)
    t.equal(CENTER_COL, 7)
  })

  t.test("horizontal placement", function() {
    const s = newGame()
    setRack(s, 0, "MAISONS")
    const r = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "MAISON", 7, 2, "H") }, { dictionary: wordDictionary() })
    t.ok(r.ok, r.message)
    t.equal(r.result.direction, "H")
    t.equal(r.state.board[7 * 15 + 2] !== null, true)
    t.equal(r.state.board[7 * 15 + 7] !== null, true)
    t.equal(r.state.players[0].rack.length, 7)
  })

  t.test("vertical placement", function() {
    const s = newGame()
    setRack(s, 0, "MOTSAIE")
    const r = previewMove(s, 0, placementsFor(s, 0, "MOT", 5, 7, "V"), wordDictionary())
    t.ok(r.valid, r.message)
    t.equal(r.direction, "V")
    t.equal(r.position, "8F")
    t.equal(r.score, 8)
  })

  t.test("later moves must connect", function() {
    const s = newGame()
    placeWord(s, "MAISON", 7, 2, "H")
    setRack(s, 0, "ETAIRSU")
    const r = previewMove(s, 0, placementsFor(s, 0, "ET", 0, 0, "H"), wordDictionary())
    t.equal(r.reason, REASON.NOT_CONNECTED)
  })

  t.test("tiles must stay on the board", function() {
    const s = newGame()
    setRack(s, 0, "MAISONS")
    const ids = s.players[0].rack
    const r = previewMove(s, 0, [{ tileId: ids[0], row: 7, col: 14 }, { tileId: ids[1], row: 7, col: 15 }], wordDictionary())
    t.equal(r.reason, REASON.OUT_OF_BOUNDS)
    const neg = previewMove(s, 0, [{ tileId: ids[0], row: -1, col: 7 }], wordDictionary())
    t.equal(neg.reason, REASON.OUT_OF_BOUNDS)
  })

  t.test("crossing words are found and validated", function() {
    const s = newGame()
    placeWord(s, "MAISON", 7, 2, "H")
    setRack(s, 0, "ASTRIEU")
    const r = previewMove(s, 0, placementsFor(s, 0, "AS", 6, 8, "V"), wordDictionary())
    t.ok(r.valid, r.message)
    t.deepEqual(r.formedWords, ["AS", "MAISONS"])
    t.equal(r.words[0].score, 3, "AS: A on double letter + S")
    t.equal(r.words[1].score, 8, "MAISONS: no premium under the new S")
    t.equal(r.score, 11)
  })
}
