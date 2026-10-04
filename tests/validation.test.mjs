import { previewMove, applyAction } from "../engine/game.mjs"
import { REASON } from "../engine/reasons.mjs"
import { newGame, setRack, placeWord, placementsFor, wordDictionary, memoryDictionary, WORDS } from "./lib/fixtures.mjs"

export const name = "Validation"

export function register(t) {
  const dict = wordDictionary()

  t.test("invalid word", function() {
    const s = newGame()
    setRack(s, 0, "MOXSAIE")
    const r = previewMove(s, 0, placementsFor(s, 0, "MOX", 7, 6, "H"), dict)
    t.equal(r.valid, false)
    t.equal(r.reason, REASON.INVALID_WORD)
    t.deepEqual(r.invalidWords, ["MOX"])
    t.deepEqual(r.formedWords, ["MOX"])
    t.ok(r.message.indexOf("MOX") !== -1)
  })

  t.test("invalid cross word (the spec example)", function() {
    const noQi = memoryDictionary(WORDS.filter(function(w) { return w !== "QI" }))
    const s = newGame()
    placeWord(s, "Q", 6, 7, "H")
    setRack(s, 0, "MAISONE")
    const r = previewMove(s, 0, placementsFor(s, 0, "MAISON", 7, 5, "H"), noQi)
    t.equal(r.valid, false)
    t.equal(r.reason, REASON.INVALID_CROSS_WORD)
    t.deepEqual(r.formedWords, ["MAISON", "QI"])
    t.deepEqual(r.invalidWords, ["QI"])
    const ok = previewMove(s, 0, placementsFor(s, 0, "MAISON", 7, 5, "H"), dict)
    t.ok(ok.valid, ok.message)
  })

  t.test("a cross word extending the main word is checked too", function() {
    const s = newGame()
    placeWord(s, "MAISON", 7, 2, "H")
    setRack(s, 0, "MEAIRTU")
    const r = previewMove(s, 0, placementsFor(s, 0, "ME", 6, 8, "V"), dict)
    t.equal(r.reason, REASON.INVALID_CROSS_WORD)
    t.deepEqual(r.invalidWords, ["MAISONE"])
  })

  t.test("disconnected move", function() {
    const s = newGame()
    placeWord(s, "MAISON", 7, 2, "H")
    setRack(s, 0, "MOTAEIU")
    t.equal(previewMove(s, 0, placementsFor(s, 0, "MOT", 12, 0, "H"), dict).reason, REASON.NOT_CONNECTED)
  })

  t.test("gap in placement", function() {
    const s = newGame()
    setRack(s, 0, "MOTAEIU")
    const ids = s.players[0].rack
    const r = previewMove(s, 0, [{ tileId: ids[0], row: 7, col: 6 }, { tileId: ids[2], row: 7, col: 8 }], dict)
    t.equal(r.reason, REASON.GAP_IN_WORD)
    t.deepEqual(r.cell, { row: 7, col: 7 })
  })

  t.test("an existing tile may fill the gap", function() {
    const s = newGame()
    placeWord(s, "O", 7, 7, "H")
    setRack(s, 0, "MTAEIUS")
    const r = previewMove(s, 0, placementsFor(s, 0, "MOT", 7, 6, "H"), dict)
    t.ok(r.valid, r.message)
    t.equal(r.score, 4, "no centre bonus: the star was already covered")
  })

  t.test("tiles must be in one line", function() {
    const s = newGame()
    setRack(s, 0, "MOTAEIU")
    const ids = s.players[0].rack
    t.equal(previewMove(s, 0, [{ tileId: ids[0], row: 7, col: 7 }, { tileId: ids[1], row: 8, col: 8 }], dict).reason, REASON.NOT_IN_LINE)
  })

  t.test("tile ownership", function() {
    const s = newGame()
    const theirs = s.players[1].rack[0]
    t.equal(previewMove(s, 0, [{ tileId: theirs, row: 7, col: 7 }], dict).reason, REASON.TILE_NOT_OWNED)
    t.equal(previewMove(s, 0, [{ tileId: s.bag[0], row: 7, col: 7 }], dict).reason, REASON.TILE_NOT_OWNED)
  })

  t.test("duplicate tile identity and position", function() {
    const s = newGame()
    const ids = s.players[0].rack
    t.equal(previewMove(s, 0, [{ tileId: ids[0], row: 7, col: 7 }, { tileId: ids[0], row: 7, col: 8 }], dict).reason, REASON.DUPLICATE_TILE)
    t.equal(previewMove(s, 0, [{ tileId: ids[0], row: 7, col: 7 }, { tileId: ids[1], row: 7, col: 7 }], dict).reason, REASON.DUPLICATE_POSITION)
  })

  t.test("occupied cell, empty and oversized moves, malformed input", function() {
    const s = newGame()
    placeWord(s, "MAISON", 7, 2, "H")
    const ids = s.players[0].rack
    t.equal(previewMove(s, 0, [{ tileId: ids[0], row: 7, col: 4 }], dict).reason, REASON.CELL_OCCUPIED)
    t.equal(previewMove(s, 0, [], dict).reason, REASON.NO_TILES)
    t.equal(previewMove(s, 0, null, dict).reason, REASON.NO_TILES)
    const eight = ids.concat([ids[0]]).map(function(id, i) { return { tileId: id, row: 0, col: i } })
    t.equal(previewMove(s, 0, eight, dict).reason, REASON.TOO_MANY_TILES)
    t.equal(previewMove(s, 0, [{ tileId: "3", row: 7, col: 8 }], dict).reason, REASON.BAD_PLACEMENT)
    t.equal(previewMove(s, 0, [{ tileId: ids[0], row: 7.5, col: 8 }], dict).reason, REASON.BAD_PLACEMENT)
  })

  t.test("joker needs a letter A–Z, and only a joker takes one", function() {
    const s = newGame()
    setRack(s, 0, "?MOAEIU")
    const joker = s.players[0].rack[0]
    const m = s.players[0].rack[1]
    const o = s.players[0].rack[2]
    const base = [{ tileId: m, row: 7, col: 6 }, { tileId: o, row: 7, col: 7 }]
    t.equal(previewMove(s, 0, base.concat([{ tileId: joker, row: 7, col: 8 }]), dict).reason, REASON.JOKER_LETTER_MISSING)
    t.equal(previewMove(s, 0, base.concat([{ tileId: joker, row: 7, col: 8, jokerLetter: "é" }]), dict).reason, REASON.JOKER_LETTER_INVALID)
    t.equal(previewMove(s, 0, base.concat([{ tileId: joker, row: 7, col: 8, jokerLetter: "TT" }]), dict).reason, REASON.JOKER_LETTER_INVALID)
    t.equal(previewMove(s, 0, [{ tileId: m, row: 7, col: 7, jokerLetter: "A" }], dict).reason, REASON.NOT_A_JOKER)
    const ok = previewMove(s, 0, base.concat([{ tileId: joker, row: 7, col: 8, jokerLetter: "T" }]), dict)
    t.ok(ok.valid, ok.message)
    t.deepEqual(ok.formedWords, ["MOT"])
    t.equal(ok.score, (2 + 1 + 0) * 2)
  })

  t.test("a joker stays a joker on the board", function() {
    const s = newGame()
    setRack(s, 0, "?MOAEIU")
    const r = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "MOt", 7, 6, "H") }, { dictionary: dict })
    t.ok(r.ok, r.message)
    const id = r.state.board[7 * 15 + 8]
    t.equal(r.state.tiles[id].isJoker, true)
    t.equal(r.state.tiles[id].letter, "?")
    t.equal(r.state.tiles[id].points, 0)
    t.equal(r.state.jokerLetters[id], "T")
    t.equal(r.state.moves[0].words[0].notation, "MO(T)")
  })

  t.test("first move must cover the centre and form a word", function() {
    const s = newGame()
    setRack(s, 0, "MOTAEIU")
    t.equal(previewMove(s, 0, placementsFor(s, 0, "MOT", 0, 0, "H"), dict).reason, REASON.FIRST_MOVE_NOT_ON_CENTER)
    t.equal(previewMove(s, 0, [{ tileId: s.players[0].rack[0], row: 7, col: 7 }], dict).reason, REASON.SINGLE_LETTER)
  })

  t.test("no dictionary means no immediate validation", function() {
    const s = newGame()
    setRack(s, 0, "MOTAEIU")
    t.equal(previewMove(s, 0, placementsFor(s, 0, "MOT", 7, 6, "H"), null).reason, REASON.DICTIONARY_UNAVAILABLE)
  })

  t.test("refused moves leave the game untouched", function() {
    const s = newGame()
    setRack(s, 0, "MOXSAIE")
    const before = JSON.stringify(s)
    const r = applyAction(s, { type: "play", player: 0, placements: placementsFor(s, 0, "MOX", 7, 6, "H") }, { dictionary: dict })
    t.equal(r.ok, false)
    t.equal(r.reason, REASON.INVALID_WORD)
    t.equal(JSON.stringify(s), before)
  })

  t.test("only the player on move may play", function() {
    const s = newGame()
    setRack(s, 1, "MOTAEIU")
    const r = applyAction(s, { type: "play", player: 1, placements: placementsFor(s, 1, "MOT", 7, 6, "H") }, { dictionary: dict })
    t.equal(r.reason, REASON.NOT_YOUR_TURN)
  })
}
