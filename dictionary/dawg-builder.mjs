// Minimal DAWG construction (Daciuk et al., incremental, sorted input) and
// packing into the edge format read by dawg.mjs.
//
// Used at build time by tools/build-dictionary.mjs, and at run time only for
// small word lists (tests, user word lists). No platform APIs.

import { Dawg } from "./dawg.mjs"

class Node {
  constructor(id) {
    this.id = id
    this.final = false
    this.tier = 0
    this.codes = []    // letter codes, ascending
    this.children = [] // Node, parallel to codes
  }

  signature() {
    let s = this.final ? "F" + this.tier : "N"
    for (let i = 0; i < this.codes.length; i++) s += "," + this.codes[i] + ":" + this.children[i].id
    return s
  }
}

export class DawgBuilder {
  constructor(alphabet, options) {
    this.alphabet = alphabet
    this.tierBits = (options && options.tierBits) || 0
    this.nextId = 0
    this.root = new Node(this.nextId++)
    this.register = new Map()
    this.unchecked = [] // [parent, code, child]
    this.previous = []
    this.words = 0
    this.finished = false
  }

  // `codes` must be strictly greater than the previous word (lexicographic on
  // codes); `tier` is stored on the word's final node.
  insert(codes, tier) {
    if (this.finished) throw new Error("builder already finished")
    let common = 0
    while (common < codes.length && common < this.previous.length && codes[common] === this.previous[common]) common++
    if (common === codes.length && common === this.previous.length)
      throw new Error("duplicate word")
    if (common < this.previous.length && common < codes.length && codes[common] < this.previous[common])
      throw new Error("words must be inserted in sorted order")
    if (common === codes.length && codes.length < this.previous.length)
      throw new Error("words must be inserted in sorted order")
    this._minimize(common)
    let node = this.unchecked.length === 0 ? this.root : this.unchecked[this.unchecked.length - 1][2]
    for (let i = common; i < codes.length; i++) {
      const next = new Node(this.nextId++)
      node.codes.push(codes[i])
      node.children.push(next)
      this.unchecked.push([node, codes[i], next])
      node = next
    }
    node.final = true
    node.tier = tier | 0
    this.previous = codes.slice()
    this.words++
  }

  _minimize(downTo) {
    for (let i = this.unchecked.length - 1; i >= downTo; i--) {
      const entry = this.unchecked[i]
      const parent = entry[0], child = entry[2]
      const sig = child.signature()
      const existing = this.register.get(sig)
      if (existing) {
        parent.children[parent.children.length - 1] = existing
      } else {
        this.register.set(sig, child)
      }
      this.unchecked.pop()
    }
  }

  // Packs the graph. Returns { edges, root, words, nodes }.
  finish() {
    this._minimize(0)
    this.finished = true

    // Topological order (parents before children) by reversed DFS post-order.
    const order = []
    const visited = new Set()
    const stack = [[this.root, 0]]
    visited.add(this.root)
    while (stack.length) {
      const top = stack[stack.length - 1]
      const node = top[0]
      if (top[1] < node.children.length) {
        const child = node.children[top[1]++]
        if (!visited.has(child)) {
          visited.add(child)
          stack.push([child, 0])
        }
      } else {
        order.push(node)
        stack.pop()
      }
    }
    order.reverse()

    const letterBits = Math.max(1, Math.ceil(Math.log2(this.alphabet.length)))
    const childShift = letterBits + 2 + this.tierBits
    const terminalBit = 1 << letterBits
    const lastBit = 1 << (letterBits + 1)
    const tierShift = letterBits + 2

    const start = new Map()
    let cursor = 1
    for (const node of order) {
      if (node.codes.length === 0) { start.set(node, 0); continue }
      start.set(node, cursor)
      cursor += node.codes.length
    }
    if (cursor >= Math.pow(2, 32 - childShift)) throw new Error("too many edges for the child field")
    const edges = new Uint32Array(cursor)
    edges[0] = lastBit // sentinel
    for (const node of order) {
      const base = start.get(node)
      for (let k = 0; k < node.codes.length; k++) {
        const child = node.children[k]
        let e = node.codes[k]
        if (child.final) e |= terminalBit | (child.tier << tierShift)
        if (k === node.codes.length - 1) e |= lastBit
        e = (e | (start.get(child) << childShift)) >>> 0
        edges[base + k] = e
      }
    }
    if (start.get(this.root) !== 1) throw new Error("root must be packed first")
    return { edges, root: 1, words: this.words, nodes: order.length, letterBits }
  }
}

// Builds a Dawg straight from a word list (any order, duplicates ignored).
// `tierOf(word)` optionally supplies a frequency tier per word.
export function buildDawg(words, alphabet, options) {
  const tierBits = (options && options.tierBits) || 0
  const tierOf = options && options.tierOf
  const keyed = []
  const seen = new Set()
  for (const w of words) {
    if (seen.has(w)) continue
    seen.add(w)
    const codes = []
    for (let i = 0; i < w.length; i++) {
      const c = alphabet.indexOf(w.charAt(i))
      if (c < 0) throw new Error("letter outside alphabet in " + w)
      codes.push(c)
    }
    keyed.push(codes)
  }
  keyed.sort(function(a, b) {
    const n = Math.min(a.length, b.length)
    for (let i = 0; i < n; i++) if (a[i] !== b[i]) return a[i] - b[i]
    return a.length - b.length
  })
  const builder = new DawgBuilder(alphabet, { tierBits: tierBits })
  for (const codes of keyed) {
    const word = codes.map(function(c) { return alphabet.charAt(c) }).join("")
    builder.insert(codes, tierOf ? tierOf(word) : 0)
  }
  const packed = builder.finish()
  const header = {
    format: "omascrabble-dawg", version: 1, alphabet: alphabet, letterBits: packed.letterBits,
    tierBits: tierBits, edges: packed.edges.length, root: packed.root, words: packed.words, checksum: ""
  }
  return new Dawg(packed.edges, header, { trusted: true })
}
