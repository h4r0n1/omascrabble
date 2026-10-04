// Tile sets. A tile set fixes the letters, their counts and their values; the
// rest of the engine never hard-codes a letter distribution, so another
// language is one more entry here plus a matching dictionary.

export const JOKER = "?"

export const TILESETS = Object.freeze({
  // French classic set: 100 letters + 2 jokers.
  "fr-classic": Object.freeze({
    id: "fr-classic",
    language: "fr",
    jokers: 2,
    letters: Object.freeze([
      ["A", 9, 1], ["B", 2, 3], ["C", 2, 3], ["D", 3, 2], ["E", 15, 1],
      ["F", 2, 4], ["G", 2, 2], ["H", 2, 4], ["I", 8, 1], ["J", 1, 8],
      ["K", 1, 10], ["L", 5, 1], ["M", 3, 2], ["N", 6, 1], ["O", 6, 1],
      ["P", 2, 3], ["Q", 1, 8], ["R", 6, 1], ["S", 6, 1], ["T", 6, 1],
      ["U", 6, 1], ["V", 2, 4], ["W", 1, 10], ["X", 1, 10], ["Y", 1, 10],
      ["Z", 1, 10]
    ])
  })
})

export function getTileset(id) {
  const set = TILESETS[id]
  if (!set) throw new Error("unknown tile set: " + id)
  return set
}

// Letter → points for a tile set (jokers are 0).
export function letterValues(tileset) {
  const values = {}
  for (const entry of tileset.letters) values[entry[0]] = entry[2]
  values[JOKER] = 0
  return values
}

export function tileCount(tileset) {
  let n = tileset.jokers
  for (const entry of tileset.letters) n += entry[1]
  return n
}

// Every physical tile of the set, with stable integer ids: letters in
// alphabetical order, then the jokers. A tile's id, letter, points and
// isJoker never change during a game; where it is and which letter a joker
// stands for live in the game state.
export function createTiles(tileset) {
  const tiles = []
  let id = 0
  for (const entry of tileset.letters) {
    for (let i = 0; i < entry[1]; i++) tiles.push(Object.freeze({ id: id++, letter: entry[0], points: entry[2], isJoker: false }))
  }
  for (let i = 0; i < tileset.jokers; i++) tiles.push(Object.freeze({ id: id++, letter: JOKER, points: 0, isJoker: true }))
  return tiles
}
