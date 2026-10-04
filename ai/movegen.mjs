// MoveGenerator: every legal placement for a rack, with its exact score.
//
// Appel & Jacobson's algorithm ("The World's Fastest Scrabble Program",
// 1988) over the compact DAWG: per row, empty squares next to a tile are
// anchors; a move is a left part built from the rack on the free squares
// before its leftmost anchor (or the tiles already there), extended to the
// right through the anchor. Cross-checks restrict each square to the letters
// that make a valid perpendicular word. Columns are handled by running the
// same code on the transposed board. Each move is produced exactly once.
//
// Scores are accumulated during the search with the same rules as the
// scoring engine (premiums only under new tiles, jokers worth 0, cross words
// scored with the new tile, bingo bonus), so a candidate never needs a second
// pass. The search allocates nothing per move: the visitor receives this
// generator and reads the current move from it, calling materialize() only
// for moves it wants to keep.
//
// Vocabulary: with `minTier` > 0 only words whose frequency tier is at least
// minTier are formed — main word and cross words alike — which is how weaker
// AI profiles genuinely do not "know" rare words.

import { PREMIUM_LAYOUT, PREMIUM, CENTER_ROW, CENTER_COL } from "../engine/board.mjs"

const N = 15
const SIZE = N * N
const ALL_LETTERS = (1 << 26) - 1
export const BLANK = 26

function multipliers(transposed) {
  const lm = new Int8Array(SIZE)
  const wm = new Int8Array(SIZE)
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
    const p = transposed ? PREMIUM_LAYOUT[c * N + r] : PREMIUM_LAYOUT[r * N + c]
    lm[r * N + c] = p === PREMIUM.DOUBLE_LETTER ? 2 : p === PREMIUM.TRIPLE_LETTER ? 3 : 1
    wm[r * N + c] = p === PREMIUM.DOUBLE_WORD || p === PREMIUM.CENTER ? 2 : p === PREMIUM.TRIPLE_WORD ? 3 : 1
  }
  return { lm: lm, wm: wm }
}

const MULT_H = multipliers(false)
const MULT_V = multipliers(true)

export class MoveGenerator {
  // `values`: points per letter code 0..25.
  constructor(graph, values) {
    this.graph = graph
    this.edges = graph.edges
    this.letterMask = graph.letterMask
    this.terminalBit = graph.terminalBit
    this.lastBit = graph.lastBit
    this.tierShift = graph.tierShift
    this.tierMask = graph.tierMask
    this.childShift = graph.childShift
    this.root = graph.root
    this.values = Int16Array.from(values)

    this.cells = new Int8Array(SIZE)      // letters in the current orientation, -1 = empty
    this.blanks = new Uint8Array(SIZE)
    this.cross = new Int32Array(SIZE)     // allowed letters per square
    this.crossScore = new Int16Array(SIZE)
    this.hasCross = new Uint8Array(SIZE)
    this.anchor = new Uint8Array(SIZE)
    this.rack = new Int8Array(27)

    this.pCol = new Int8Array(N)
    this.pLetter = new Int8Array(N)
    this.pBlank = new Uint8Array(N)
    this.pCount = 0
    this.prefix = new Int8Array(N)
    this.prefixBlank = new Uint8Array(N)

    // Current move, valid inside visitor.onMove().
    this.transposed = false
    this.row = 0
    this.anchorCol = 0
    this.startCol = 0
    this.endCol = 0
    this.score = 0
    this.tilesUsed = 0
    this.moveCount = 0
    this.nodesVisited = 0
  }

  // board: Int8Array(225) letter codes (-1 empty); blankBoard: Uint8Array(225);
  // rackCounts: Int8Array(27) (index 26 = jokers).
  // options: { minTier, bingoTiles, bingoBonus }
  // visitor.onMove(gen) is called once per legal move.
  generate(board, blankBoard, rackCounts, options, visitor) {
    this.minTier = options && options.minTier ? options.minTier : 0
    this.bingoTiles = options && options.bingoTiles ? options.bingoTiles : 7
    this.bingoBonus = options && options.bingoBonus !== undefined ? options.bingoBonus : 50
    this.visitor = visitor
    this.moveCount = 0
    this.nodesVisited = 0
    for (let i = 0; i < 27; i++) this.rack[i] = rackCounts[i]
    let rackTiles = 0
    for (let i = 0; i < 27; i++) rackTiles += this.rack[i]
    if (rackTiles === 0) return 0
    this.rackTiles = rackTiles
    let empty = true
    for (let i = 0; i < SIZE; i++) if (board[i] >= 0) { empty = false; break }
    this.emptyBoard = empty
    this._orient(board, blankBoard, false)
    this._generateAll()
    this._orient(board, blankBoard, true)
    this._generateAll()
    this.visitor = null
    return this.moveCount
  }

  _orient(board, blankBoard, transposed) {
    this.transposed = transposed
    const cells = this.cells, blanks = this.blanks
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
      const src = transposed ? c * N + r : r * N + c
      cells[r * N + c] = board[src]
      blanks[r * N + c] = blankBoard[src]
    }
    const mult = transposed ? MULT_V : MULT_H
    this.lm = mult.lm
    this.wm = mult.wm
    this._computeCrossChecks()
    this._computeAnchors()
  }

  _computeAnchors() {
    const cells = this.cells, anchor = this.anchor
    for (let i = 0; i < SIZE; i++) anchor[i] = 0
    if (this.emptyBoard) {
      anchor[CENTER_ROW * N + CENTER_COL] = 1
      return
    }
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
      const i = r * N + c
      if (cells[i] >= 0) continue
      if ((r > 0 && cells[i - N] >= 0) || (r < N - 1 && cells[i + N] >= 0)
          || (c > 0 && cells[i - 1] >= 0) || (c < N - 1 && cells[i + 1] >= 0)) anchor[i] = 1
    }
  }

  _computeCrossChecks() {
    const cells = this.cells, blanks = this.blanks, edges = this.edges
    const values = this.values
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
      const i = r * N + c
      this.hasCross[i] = 0
      this.crossScore[i] = 0
      if (cells[i] >= 0) { this.cross[i] = 0; continue }
      const up = r > 0 && cells[i - N] >= 0
      const down = r < N - 1 && cells[i + N] >= 0
      if (!up && !down) { this.cross[i] = ALL_LETTERS; continue }
      let top = r
      while (top > 0 && cells[(top - 1) * N + c] >= 0) top--
      let bottom = r
      while (bottom < N - 1 && cells[(bottom + 1) * N + c] >= 0) bottom++
      let score = 0
      for (let k = top; k <= bottom; k++) if (k !== r && !blanks[k * N + c]) score += values[cells[k * N + c]]
      this.hasCross[i] = 1
      this.crossScore[i] = score
      // Walk the letters above, then try every letter at (r, c) followed by
      // the letters below.
      let node = this.root
      let ok = true
      for (let k = top; k < r; k++) {
        const e = this._findEdge(node, cells[k * N + c])
        if (e < 0) { ok = false; break }
        node = edges[e] >>> this.childShift
      }
      let mask = 0
      if (ok && node > 0) {
        for (let e = node; ; e++) {
          const edge = edges[e]
          const letter = edge & this.letterMask
          if (bottom === r) {
            if ((edge & this.terminalBit) && ((edge >>> this.tierShift) & this.tierMask) >= this.minTier) mask |= 1 << letter
          } else {
            let n2 = edge >>> this.childShift
            let last = -1
            for (let k = r + 1; k <= bottom; k++) {
              last = this._findEdge(n2, cells[k * N + c])
              if (last < 0) break
              n2 = edges[last] >>> this.childShift
            }
            if (last >= 0 && (edges[last] & this.terminalBit) && ((edges[last] >>> this.tierShift) & this.tierMask) >= this.minTier)
              mask |= 1 << letter
          }
          if (edge & this.lastBit) break
        }
      }
      this.cross[i] = mask
    }
  }

  _findEdge(node, code) {
    if (node <= 0) return -1
    const edges = this.edges
    for (let i = node; ; i++) {
      const e = edges[i]
      const l = e & this.letterMask
      if (l === code) return i
      if (l > code || (e & this.lastBit)) return -1
    }
  }

  _generateAll() {
    const cells = this.cells, anchor = this.anchor, edges = this.edges
    for (let r = 0; r < N; r++) {
      this.row = r
      for (let a = 0; a < N; a++) {
        if (!anchor[r * N + a]) continue
        this.anchorCol = a
        if (a > 0 && cells[r * N + a - 1] >= 0) {
          // The word starts with the tiles already left of the anchor.
          let start = a - 1
          while (start > 0 && cells[r * N + start - 1] >= 0) start--
          let node = this.root
          let sum = 0
          let ok = true
          for (let c = start; c < a; c++) {
            const e = this._findEdge(node, cells[r * N + c])
            if (e < 0) { ok = false; break }
            node = edges[e] >>> this.childShift
            if (!this.blanks[r * N + c]) sum += this.values[cells[r * N + c]]
          }
          if (ok && node > 0) {
            this.pCount = 0
            this._extendRight(node, a, sum, 1, 0, 0, start, 0, 0)
          }
        } else {
          let limit = 0
          let c = a - 1
          while (c >= 0 && cells[r * N + c] < 0 && !anchor[r * N + c]) { limit++; c-- }
          if (limit > this.rackTiles - 1) limit = this.rackTiles - 1
          this._leftPart(this.root, limit, 0)
        }
      }
    }
  }

  _leftPart(node, limit, k) {
    this._extendFromLeft(node, k)
    if (limit <= 0 || node <= 0) return
    const edges = this.edges, rack = this.rack
    for (let e = node; ; e++) {
      const edge = edges[e]
      const letter = edge & this.letterMask
      const child = edge >>> this.childShift
      if (child > 0) {
        if (rack[letter] > 0) {
          rack[letter]--
          this.prefix[k] = letter
          this.prefixBlank[k] = 0
          this._leftPart(child, limit - 1, k + 1)
          rack[letter]++
        }
        if (rack[BLANK] > 0) {
          rack[BLANK]--
          this.prefix[k] = letter
          this.prefixBlank[k] = 1
          this._leftPart(child, limit - 1, k + 1)
          rack[BLANK]++
        }
      }
      if (edge & this.lastBit) break
    }
  }

  _extendFromLeft(node, k) {
    if (node <= 0) return
    const r = this.row, a = this.anchorCol
    const start = a - k
    let sum = 0, mult = 1
    this.pCount = 0
    for (let i = 0; i < k; i++) {
      const col = start + i
      const idx = r * N + col
      const v = this.prefixBlank[i] ? 0 : this.values[this.prefix[i]]
      sum += v * this.lm[idx]
      mult *= this.wm[idx]
      this.pCol[i] = col
      this.pLetter[i] = this.prefix[i]
      this.pBlank[i] = this.prefixBlank[i]
    }
    this.pCount = k
    this._extendRight(node, a, sum, mult, 0, k, start, 0, 0)
    this.pCount = 0
  }

  _extendRight(node, col, sum, mult, crossSum, tiles, start, lastTerminal, lastTier) {
    this.nodesVisited++
    const r = this.row
    const idx = r * N + col
    if (col >= N || this.cells[idx] < 0) {
      if (col > this.anchorCol && lastTerminal && tiles > 0 && lastTier >= this.minTier) this._record(sum, mult, crossSum, tiles, start, col)
      if (col >= N || node <= 0) return
      const edges = this.edges, rack = this.rack
      const allowed = this.cross[idx]
      const lm = this.lm[idx], wm = this.wm[idx]
      const crossing = this.hasCross[idx]
      const crossBase = this.crossScore[idx]
      for (let e = node; ; e++) {
        const edge = edges[e]
        const letter = edge & this.letterMask
        if (allowed & (1 << letter)) {
          const child = edge >>> this.childShift
          const term = edge & this.terminalBit
          const tier = (edge >>> this.tierShift) & this.tierMask
          if (rack[letter] > 0) {
            rack[letter]--
            const p = this.pCount++
            this.pCol[p] = col; this.pLetter[p] = letter; this.pBlank[p] = 0
            const v = this.values[letter] * lm
            this._extendRight(child, col + 1, sum + v, mult * wm, crossing ? crossSum + (crossBase + v) * wm : crossSum, tiles + 1, start, term, tier)
            this.pCount--
            rack[letter]++
          }
          if (rack[BLANK] > 0) {
            rack[BLANK]--
            const p = this.pCount++
            this.pCol[p] = col; this.pLetter[p] = letter; this.pBlank[p] = 1
            this._extendRight(child, col + 1, sum, mult * wm, crossing ? crossSum + crossBase * wm : crossSum, tiles + 1, start, term, tier)
            this.pCount--
            rack[BLANK]++
          }
        }
        if (edge & this.lastBit) break
      }
    } else {
      const e = this._findEdge(node, this.cells[idx])
      if (e < 0) return
      const edge = this.edges[e]
      const v = this.blanks[idx] ? 0 : this.values[this.cells[idx]]
      this._extendRight(edge >>> this.childShift, col + 1, sum + v, mult, crossSum, tiles, start,
        edge & this.terminalBit, (edge >>> this.tierShift) & this.tierMask)
    }
  }

  _record(sum, mult, crossSum, tiles, start, end) {
    // A single tile with neighbours across was already produced by the
    // horizontal pass as part of that word.
    if (this.transposed && tiles === 1 && this.hasCross[this.row * N + this.pCol[0]]) return
    this.score = sum * mult + crossSum + (tiles >= this.bingoTiles ? this.bingoBonus : 0)
    this.tilesUsed = tiles
    this.startCol = start
    this.endCol = end
    this.moveCount++
    this.visitor.onMove(this)
  }

  // The current move in board coordinates:
  // { dir, row, col, word, score, tiles: [{ row, col, letter, blank }] }.
  materialize(alphabet) {
    const letters = alphabet || "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    const tiles = []
    for (let i = 0; i < this.pCount; i++) {
      const c = this.pCol[i]
      tiles.push(this.transposed
        ? { row: c, col: this.row, letter: letters.charAt(this.pLetter[i]), blank: this.pBlank[i] === 1 }
        : { row: this.row, col: c, letter: letters.charAt(this.pLetter[i]), blank: this.pBlank[i] === 1 })
    }
    let word = ""
    for (let c = this.startCol; c < this.endCol; c++) {
      const idx = this.row * N + c
      if (this.cells[idx] >= 0) { word += letters.charAt(this.cells[idx]); continue }
      for (let i = 0; i < this.pCount; i++) if (this.pCol[i] === c) { word += letters.charAt(this.pLetter[i]); break }
    }
    return {
      dir: this.transposed ? "V" : "H",
      row: this.transposed ? this.startCol : this.row,
      col: this.transposed ? this.row : this.startCol,
      word: word,
      score: this.score,
      tilesUsed: this.tilesUsed,
      tiles: tiles
    }
  }
}

// Builds the generator's board arrays from a public view's cells
// ([{ letter, isJoker }] or null).
export function boardArrays(cells) {
  const board = new Int8Array(SIZE).fill(-1)
  const blanks = new Uint8Array(SIZE)
  for (let i = 0; i < SIZE; i++) {
    const cell = cells[i]
    if (!cell) continue
    board[i] = cell.letter.charCodeAt(0) - 65
    blanks[i] = cell.isJoker ? 1 : 0
  }
  return { board: board, blanks: blanks }
}

export function rackCounts(rack) {
  const counts = new Int8Array(27)
  for (const t of rack) {
    if (t.isJoker) counts[BLANK]++
    else counts[t.letter.charCodeAt(0) - 65]++
  }
  return counts
}
