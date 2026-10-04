// Test fixtures: a small word list and helpers to arrange positions without
// breaking tile conservation (every tile stays in exactly one place).

import { createGame, MODE } from "../../engine/game.mjs"
import { cellIndex } from "../../engine/board.mjs"
import { MemoryDictionaryProvider, DawgDictionaryProvider } from "../../dictionary/provider.mjs"
import { buildDawg } from "../../dictionary/dawg-builder.mjs"
import { TILE_ALPHABET } from "../../dictionary/normalize.mjs"

export const WORDS = [
  "MAISON", "MAISONS", "MOTION", "MOTIONS", "MOT", "MOTS", "QI", "AS", "SA", "MA", "ME", "MI", "ON", "OS", "OU",
  "JOUER", "JOUE", "JOUES", "JE", "TE", "TES", "ET", "ES", "EST", "TA", "TU", "NU", "NE", "SI", "IL", "LA", "LE",
  "RATE", "RATES", "TARE", "TARES", "TRES", "ARTISTE", "ARTISTES", "RATIONS", "ARETIER", "ZOO", "ZOOS", "KIWI",
  "DE", "DES", "DO", "ODE", "ODES", "AI", "AN", "ANS", "SAC", "SACS", "CAS", "LAC", "CLE", "CLES", "ETE", "ETES",
  "ABAT", "ABATS", "BAS", "BAT", "TABAC", "EAU", "EAUX", "AU", "AUX", "XI", "WU", "YA"
]

export function wordDictionary(words) {
  const list = words || WORDS
  const graph = buildDawg(list, TILE_ALPHABET, { tierBits: 2, tierOf: function() { return 3 } })
  return new DawgDictionaryProvider(graph, { id: "test", name: "Test", language: "fr", version: "test" })
}

export function memoryDictionary(words) {
  return new MemoryDictionaryProvider(words || WORDS)
}

export function newGame(options) {
  return createGame(Object.assign({
    mode: MODE.HUMAN_VS_HUMAN,
    players: [{ name: "A", kind: "human" }, { name: "B", kind: "human" }],
    seed: 42,
    now: Date.UTC(2026, 9, 4, 12, 0, 0),
    dictionary: { id: "test", name: "Test", version: "test", official: false }
  }, options || {}))
}

// Takes a tile showing `letter` ("?" for a joker) from the bag, or failing
// that from any rack not in `protect`. Returns its id.
function takeTile(state, letter, protect) {
  const matches = function(id) { return state.tiles[id].letter === letter }
  let i = state.bag.findIndex(matches)
  if (i !== -1) return state.bag.splice(i, 1)[0]
  for (let p = 0; p < state.players.length; p++) {
    if (protect.indexOf(p) !== -1) continue
    const rack = state.players[p].rack
    i = rack.findIndex(matches)
    if (i !== -1) {
      const id = rack.splice(i, 1)[0]
      // keep that rack full with something from the bag
      if (state.bag.length) rack.push(state.bag.shift())
      return id
    }
  }
  throw new Error("no tile left for " + letter)
}

// Gives player `p` exactly `letters` ("?" = joker). Returns the rack ids.
export function setRack(state, p, letters) {
  const rack = state.players[p].rack
  while (rack.length) state.bag.push(rack.pop())
  for (const ch of letters) rack.push(takeTile(state, ch, [p]))
  return rack.slice()
}

// Puts `word` on the board without playing it. Lowercase letters are jokers
// standing for that letter. Returns the tile ids placed.
export function placeWord(state, word, row, col, dir) {
  const ids = []
  for (let k = 0; k < word.length; k++) {
    const r = dir === "V" ? row + k : row
    const c = dir === "H" ? col + k : col
    const ch = word.charAt(k)
    const isJoker = ch !== ch.toUpperCase()
    const id = takeTile(state, isJoker ? "?" : ch, [])
    state.board[cellIndex(r, c)] = id
    if (isJoker) state.jokerLetters[id] = ch.toUpperCase()
    ids.push(id)
  }
  return ids
}

// Placements for `word` from player `p`'s rack, starting at (row, col).
// Cells already occupied are skipped (they must hold the right letter).
// Lowercase letters use a joker.
export function placementsFor(state, p, word, row, col, dir) {
  const rack = state.players[p].rack.slice()
  const out = []
  for (let k = 0; k < word.length; k++) {
    const r = dir === "V" ? row + k : row
    const c = dir === "H" ? col + k : col
    if (state.board[cellIndex(r, c)] !== null) continue
    const ch = word.charAt(k)
    const isJoker = ch !== ch.toUpperCase()
    const i = rack.findIndex(function(id) { return state.tiles[id].letter === (isJoker ? "?" : ch) })
    if (i === -1) throw new Error("rack lacks " + ch)
    const id = rack.splice(i, 1)[0]
    out.push(isJoker ? { tileId: id, row: r, col: c, jokerLetter: ch.toUpperCase() } : { tileId: id, row: r, col: c })
  }
  return out
}

export function tileConservation(state) {
  const seen = new Array(state.tiles.length).fill(0)
  for (const id of state.board) if (id !== null) seen[id]++
  for (const p of state.players) for (const id of p.rack) seen[id]++
  for (const id of state.bag) seen[id]++
  return seen.every(function(n) { return n === 1 })
}
