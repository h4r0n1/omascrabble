// The 15 × 15 board: a deterministic row-major matrix of cells, each with a
// fixed premium type and at most one tile.
//
// A premium square only counts for the move that first covers it (the
// scoring engine sees `isNew`), so the board needs no "used" flag: an
// occupied square's premium is spent by definition.

export const BOARD_SIZE = 15
export const CELL_COUNT = BOARD_SIZE * BOARD_SIZE

export const PREMIUM = Object.freeze({
  NONE: "NONE",
  DOUBLE_LETTER: "DOUBLE_LETTER",
  TRIPLE_LETTER: "TRIPLE_LETTER",
  DOUBLE_WORD: "DOUBLE_WORD",
  TRIPLE_WORD: "TRIPLE_WORD",
  CENTER: "CENTER"
})

export const CENTER_ROW = 7
export const CENTER_COL = 7

// One representative per symmetry class; the layout is the closure of these
// under the board's eight symmetries.
const BASE_PREMIUMS = [
  [PREMIUM.TRIPLE_WORD, [[0, 0], [0, 7]]],
  [PREMIUM.DOUBLE_WORD, [[1, 1], [2, 2], [3, 3], [4, 4]]],
  [PREMIUM.TRIPLE_LETTER, [[1, 5], [5, 5]]],
  [PREMIUM.DOUBLE_LETTER, [[0, 3], [2, 6], [3, 7], [6, 6]]],
  [PREMIUM.CENTER, [[7, 7]]]
]

export const PREMIUM_LAYOUT = Object.freeze((function() {
  const layout = new Array(CELL_COUNT).fill(PREMIUM.NONE)
  const m = BOARD_SIZE - 1
  for (const entry of BASE_PREMIUMS) {
    for (const rc of entry[1]) {
      const r = rc[0], c = rc[1]
      const images = [[r, c], [c, r], [m - r, c], [r, m - c], [m - r, m - c], [c, m - r], [m - c, r], [m - c, m - r]]
      for (const im of images) layout[im[0] * BOARD_SIZE + im[1]] = entry[0]
    }
  }
  return layout
})())

export function cellIndex(row, col) {
  return row * BOARD_SIZE + col
}

export function inBounds(row, col) {
  return Number.isInteger(row) && Number.isInteger(col) && row >= 0 && col >= 0 && row < BOARD_SIZE && col < BOARD_SIZE
}

export function premiumAt(row, col) {
  return inBounds(row, col) ? PREMIUM_LAYOUT[cellIndex(row, col)] : PREMIUM.NONE
}

export function letterMultiplier(premium) {
  if (premium === PREMIUM.DOUBLE_LETTER) return 2
  if (premium === PREMIUM.TRIPLE_LETTER) return 3
  return 1
}

export function wordMultiplier(premium) {
  if (premium === PREMIUM.DOUBLE_WORD || premium === PREMIUM.CENTER) return 2
  if (premium === PREMIUM.TRIPLE_WORD) return 3
  return 1
}

// Board tiles are { id, letter, points, isJoker, jokerLetter }. For a joker,
// `letter` stays "?" and `jokerLetter` holds the letter it stands for: a
// joker is never turned into a normal tile.
export function effectiveLetter(tile) {
  if (!tile) return ""
  return tile.isJoker ? (tile.jokerLetter || "") : tile.letter
}

export class Board {
  constructor(tiles) {
    this.tiles = tiles ? tiles.slice() : new Array(CELL_COUNT).fill(null)
    if (this.tiles.length !== CELL_COUNT) throw new Error("board must have " + CELL_COUNT + " cells")
  }

  clone() { return new Board(this.tiles) }

  get(row, col) {
    return inBounds(row, col) ? this.tiles[cellIndex(row, col)] : null
  }

  set(row, col, tile) {
    if (!inBounds(row, col)) throw new Error("cell out of bounds: " + row + "," + col)
    this.tiles[cellIndex(row, col)] = tile || null
  }

  isEmpty(row, col) {
    return inBounds(row, col) && this.tiles[cellIndex(row, col)] === null
  }

  isOccupied(row, col) {
    return inBounds(row, col) && this.tiles[cellIndex(row, col)] !== null
  }

  letterAt(row, col) {
    return effectiveLetter(this.get(row, col))
  }

  isEmptyBoard() {
    for (let i = 0; i < CELL_COUNT; i++) if (this.tiles[i] !== null) return false
    return true
  }

  tileCount() {
    let n = 0
    for (let i = 0; i < CELL_COUNT; i++) if (this.tiles[i] !== null) n++
    return n
  }

  cell(row, col) {
    return { row: row, column: col, premiumType: premiumAt(row, col), tile: this.get(row, col) }
  }

  // The full matrix as rows of { row, column, premiumType, tile } cells.
  toMatrix() {
    const rows = []
    for (let r = 0; r < BOARD_SIZE; r++) {
      const row = []
      for (let c = 0; c < BOARD_SIZE; c++) row.push(this.cell(r, c))
      rows.push(row)
    }
    return rows
  }

  hasNeighbor(row, col) {
    return this.isOccupied(row - 1, col) || this.isOccupied(row + 1, col)
      || this.isOccupied(row, col - 1) || this.isOccupied(row, col + 1)
  }
}
