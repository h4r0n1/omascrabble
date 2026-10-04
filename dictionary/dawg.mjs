// Compact DAWG (directed acyclic word graph) reader.
//
// The compiled dictionary is a minimal acyclic automaton packed into one
// Uint32Array of edges. Each node is a contiguous run of edges sorted by
// letter; the last edge of a run has the LAST flag. An edge packs:
//
//   bits 0 .. L-1          letter index into the header's alphabet
//   bit  L                 TERMINAL — the path ending with this edge is a word
//   bit  L+1               LAST — last edge of its node
//   bits L+2 .. L+2+T-1    frequency tier of the word (meaningful if TERMINAL)
//   remaining high bits    index of the child node's first edge, 0 = no child
//
// where L = header.letterBits and T = header.tierBits. Index 0 is a sentinel,
// so "child 0" means the path ends there. Nodes are packed in topological
// order: a child always starts after the edge that points to it, which the
// validator checks — a corrupt or hostile file therefore cannot make any
// traversal loop.
//
// File format: one line of JSON header, a newline, then the edges as base64
// (little-endian bytes) on a single line. The data is parsed, never executed.

export const DAWG_FORMAT = "omascrabble-dawg"
export const DAWG_VERSION = 1

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
const B64_LOOKUP = (function() {
  const t = new Int16Array(128).fill(-1)
  for (let i = 0; i < B64.length; i++) t[B64.charCodeAt(i)] = i
  return t
})()

export class DawgError extends Error {
  constructor(code, message) {
    super(message)
    this.name = "DawgError"
    this.code = code
  }
}

export function checksumEdges(edges) {
  let h = 0x811c9dc5 | 0
  for (let i = 0; i < edges.length; i++) {
    h ^= edges[i]
    h = Math.imul(h, 16777619)
  }
  return (h >>> 0).toString(16).padStart(8, "0")
}

// Splits "header\npayload" and parses the header. Throws DawgError.
export function parseDawgHeader(text) {
  if (typeof text !== "string" || text.length === 0) throw new DawgError("EMPTY", "dictionary file is empty")
  const nl = text.indexOf("\n")
  if (nl <= 0) throw new DawgError("NO_HEADER", "dictionary header missing")
  let header
  try {
    header = JSON.parse(text.slice(0, nl))
  } catch (e) {
    throw new DawgError("BAD_HEADER", "dictionary header is not valid JSON")
  }
  if (!header || typeof header !== "object" || Array.isArray(header))
    throw new DawgError("BAD_HEADER", "dictionary header is not an object")
  if (header.format !== DAWG_FORMAT) throw new DawgError("BAD_FORMAT", "not an omascrabble dictionary")
  if (header.version !== DAWG_VERSION) throw new DawgError("BAD_VERSION", "unsupported dictionary format version " + header.version)
  const intIn = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi
  if (typeof header.alphabet !== "string" || header.alphabet.length < 1 || header.alphabet.length > 64)
    throw new DawgError("BAD_HEADER", "bad alphabet")
  if (!intIn(header.letterBits, 1, 6) || (1 << header.letterBits) < header.alphabet.length)
    throw new DawgError("BAD_HEADER", "bad letterBits")
  if (!intIn(header.tierBits, 0, 3)) throw new DawgError("BAD_HEADER", "bad tierBits")
  if (!intIn(header.edges, 2, 1 << 24)) throw new DawgError("BAD_HEADER", "bad edge count")
  if (!intIn(header.root, 1, header.edges - 1)) throw new DawgError("BAD_HEADER", "bad root")
  if (!intIn(header.words, 0, 1 << 26)) throw new DawgError("BAD_HEADER", "bad word count")
  if (typeof header.checksum !== "string") throw new DawgError("BAD_HEADER", "missing checksum")
  const childBits = 32 - header.letterBits - 2 - header.tierBits
  if (header.edges >= Math.pow(2, childBits)) throw new DawgError("BAD_HEADER", "edge count exceeds child field")
  return { header: header, payloadStart: nl + 1 }
}

const LITTLE_ENDIAN = new Uint8Array(new Uint32Array([1]).buffer)[0] === 1

// Incremental base64 → Uint32Array decoder, so a UI thread can spread the
// work over several frames. `step(budget)` decodes up to `budget` characters
// and returns true when finished.
export class DawgDecoder {
  constructor(text) {
    const parsed = parseDawgHeader(text)
    this.header = parsed.header
    this.text = text
    this.pos = parsed.payloadStart
    this.end = text.length
    while (this.end > this.pos && isSpace(text.charCodeAt(this.end - 1))) this.end--
    this.totalBytes = this.header.edges * 4
    if (this.end - this.pos < Math.ceil(this.totalBytes / 3) * 4)
      throw new DawgError("TRUNCATED", "dictionary payload is truncated")
    this.bytes = new Uint8Array(this.totalBytes)
    this.byteIndex = 0
    this.done = false
  }

  get progress() { return this.totalBytes ? this.byteIndex / this.totalBytes : 1 }

  step(budget) {
    if (this.done) return true
    const text = this.text
    const lookup = B64_LOOKUP
    const bytes = this.bytes
    const total = this.totalBytes
    let bi = this.byteIndex
    let pos = this.pos
    const quads = Math.max(1, Math.floor((budget || 0) / 4))
    const stop = Math.min(this.end, pos + quads * 4)
    let padded = false
    while (pos + 4 <= stop) {
      const c0 = text.charCodeAt(pos), c1 = text.charCodeAt(pos + 1)
      const c2 = text.charCodeAt(pos + 2), c3 = text.charCodeAt(pos + 3)
      const a = c0 < 128 ? lookup[c0] : -1
      const b = c1 < 128 ? lookup[c1] : -1
      if (a < 0 || b < 0) throw new DawgError("BAD_PAYLOAD", "invalid character in dictionary payload")
      if (bi < total) bytes[bi++] = (a << 2) | (b >> 4)
      if (c2 === 61) { padded = true; pos += 4; break }
      const c = c2 < 128 ? lookup[c2] : -1
      if (c < 0) throw new DawgError("BAD_PAYLOAD", "invalid character in dictionary payload")
      if (bi < total) bytes[bi++] = ((b & 15) << 4) | (c >> 2)
      if (c3 === 61) { padded = true; pos += 4; break }
      const d = c3 < 128 ? lookup[c3] : -1
      if (d < 0) throw new DawgError("BAD_PAYLOAD", "invalid character in dictionary payload")
      if (bi < total) bytes[bi++] = ((c & 3) << 6) | d
      pos += 4
    }
    this.byteIndex = bi
    this.pos = pos
    // Done once every byte is in, or when no complete quad is left — the
    // latter is only an error if bytes are still missing. This also means a
    // malformed payload can never stall a caller that loops on step().
    if (bi >= total || padded || pos + 4 > this.end) {
      if (bi < total) throw new DawgError("TRUNCATED", "dictionary payload is truncated")
      this.done = true
      this.text = null
    }
    return this.done
  }

  // Moves the decoded bytes into a Uint32Array once the payload is complete.
  _edgesFromBytes() {
    let edges
    if (LITTLE_ENDIAN) {
      edges = new Uint32Array(this.bytes.buffer)
    } else {
      edges = new Uint32Array(this.header.edges)
      const b = this.bytes
      for (let i = 0, j = 0; i < edges.length; i++, j += 4)
        edges[i] = (b[j] | (b[j + 1] << 8) | (b[j + 2] << 16) | (b[j + 3] << 24)) >>> 0
    }
    this.bytes = null
    return edges
  }

  // Finishes decoding, validates, and returns the Dawg.
  finish() {
    while (!this.done) this.step(1 << 20)
    return new Dawg(this._edgesFromBytes(), this.header)
  }
}

// Decodes and validates in slices so a UI thread never blocks for more than a
// few milliseconds: call step() from a timer until it returns true, then read
// `dawg`. Errors are thrown as DawgError from step().
export class DawgLoader {
  constructor(text) {
    this.decoder = new DawgDecoder(text)
    this.validator = null
    this.dawg = null
    this.phase = "decode"
  }

  get progress() {
    if (this.phase === "decode") return this.decoder.progress * 0.5
    if (this.phase === "validate") return 0.5 + this.validator.progress * 0.5
    return 1
  }

  // `budget` is roughly the number of characters (decode) or edges
  // (validation) to process in this slice.
  step(budget) {
    if (this.phase === "decode") {
      if (this.decoder.step(budget)) {
        this.validator = new DawgValidator(this.decoder._edgesFromBytes(), this.decoder.header)
        this.phase = "validate"
      }
      return false
    }
    if (this.phase === "validate") {
      if (this.validator.step(budget)) {
        this.dawg = new Dawg(this.validator.edges, this.validator.header, { trusted: true })
        this.validator = null
        this.decoder = null
        this.phase = "done"
      }
      return this.phase === "done"
    }
    return true
  }
}

// Integrity and safety checks over a decoded edge array, resumable in slices:
// checksum, then per-edge structure (letters in range, child pointers forward
// and in bounds, no dead ends), then a reverse pass that counts the words and
// compares with the header.
export class DawgValidator {
  constructor(edges, header) {
    this.edges = edges
    this.header = header
    const L = header.letterBits
    this.letterMask = (1 << L) - 1
    this.terminalBit = 1 << L
    this.lastBit = 1 << (L + 1)
    this.childShift = L + 2 + header.tierBits
    this.phase = 0
    this.i = 0
    this.hash = 0x811c9dc5 | 0
    this.counts = null
  }

  get progress() {
    const n = this.edges.length
    return Math.min(1, (this.phase * n + (this.phase === 2 ? n - this.i : this.i)) / (3 * n))
  }

  step(budget) {
    const edges = this.edges
    const n = edges.length
    let remaining = Math.max(1024, budget | 0)
    while (remaining > 0 && this.phase < 3) {
      if (this.phase === 0) {
        let h = this.hash
        const end = Math.min(n, this.i + remaining)
        for (let i = this.i; i < end; i++) {
          h ^= edges[i]
          h = Math.imul(h, 16777619)
        }
        remaining -= end - this.i
        this.i = end
        this.hash = h
        if (end === n) {
          if ((h >>> 0).toString(16).padStart(8, "0") !== this.header.checksum)
            throw new DawgError("BAD_CHECKSUM", "dictionary checksum mismatch")
          if (!(edges[n - 1] & this.lastBit)) throw new DawgError("BAD_STRUCTURE", "unterminated edge list")
          this.phase = 1
          this.i = 1
        }
      } else if (this.phase === 1) {
        const alphabetSize = this.header.alphabet.length
        const end = Math.min(n, this.i + remaining)
        for (let i = this.i; i < end; i++) {
          const e = edges[i]
          if ((e & this.letterMask) >= alphabetSize) throw new DawgError("BAD_STRUCTURE", "letter out of range at edge " + i)
          const child = e >>> this.childShift
          if (child !== 0 && (child <= i || child >= n)) throw new DawgError("BAD_STRUCTURE", "bad child pointer at edge " + i)
          if (child === 0 && !(e & this.terminalBit)) throw new DawgError("BAD_STRUCTURE", "dead-end edge at edge " + i)
        }
        remaining -= end - this.i
        this.i = end
        if (end === n) {
          this.phase = 2
          this.i = n - 1
          this.counts = new Float64Array(n + 1)
        }
      } else {
        // Reverse topological order: a child always sits at a higher index
        // than its parent edge, so walking from the end visits every child
        // node before any edge that leads to it. counts[i] = words reachable
        // through edges i, i+1, … to the end of this node's run.
        const counts = this.counts
        const stop = Math.max(1, this.i - remaining + 1)
        for (let i = this.i; i >= stop; i--) {
          const e = edges[i]
          const child = e >>> this.childShift
          let c = (e & this.terminalBit) ? 1 : 0
          if (child !== 0) c += counts[child]
          counts[i] = c + ((e & this.lastBit) ? 0 : counts[i + 1])
        }
        remaining -= this.i - stop + 1
        this.i = stop - 1
        if (this.i < 1) {
          const total = counts[this.header.root]
          this.counts = null
          if (total !== this.header.words)
            throw new DawgError("BAD_STRUCTURE", "word count mismatch (" + total + " != " + this.header.words + ")")
          this.phase = 3
        }
      }
    }
    return this.phase === 3
  }
}

function isSpace(c) { return c === 10 || c === 13 || c === 32 || c === 9 }

export function decodeDawg(text) {
  return new DawgDecoder(text).finish()
}

export class Dawg {
  constructor(edges, header, options) {
    this.edges = edges
    this.header = header
    this.alphabet = header.alphabet
    this.letterBits = header.letterBits
    this.tierBits = header.tierBits
    this.letterMask = (1 << header.letterBits) - 1
    this.terminalBit = 1 << header.letterBits
    this.lastBit = 1 << (header.letterBits + 1)
    this.tierShift = header.letterBits + 2
    this.tierMask = (1 << header.tierBits) - 1
    this.childShift = header.letterBits + 2 + header.tierBits
    this.root = header.root
    this.wordCount = header.words
    // Untrusted edges are validated synchronously unless the caller (the
    // sliced DawgLoader) already did it.
    if (!(options && options.trusted)) {
      const validator = new DawgValidator(edges, header)
      while (!validator.step(1 << 22)) { /* runs to completion */ }
    }
  }

  letterCode(ch) {
    return this.alphabet.indexOf(ch)
  }

  // Returns the edge index for `code` in the node starting at `node`, or -1.
  findEdge(node, code) {
    if (node <= 0) return -1
    const edges = this.edges
    for (let i = node; ; i++) {
      const e = edges[i]
      const l = e & this.letterMask
      if (l === code) return i
      if (l > code || (e & this.lastBit)) return -1
    }
  }

  isTerminal(edgeIndex) { return (this.edges[edgeIndex] & this.terminalBit) !== 0 }
  childOf(edgeIndex) { return this.edges[edgeIndex] >>> this.childShift }
  tierOfEdge(edgeIndex) { return (this.edges[edgeIndex] >>> this.tierShift) & this.tierMask }
  letterOf(edgeIndex) { return this.edges[edgeIndex] & this.letterMask }
  isLast(edgeIndex) { return (this.edges[edgeIndex] & this.lastBit) !== 0 }

  // Follows `codes` (array of letter codes) from the root; returns the final
  // edge index or -1.
  walkCodes(codes, from) {
    let node = from === undefined ? this.root : from
    let edge = -1
    for (let i = 0; i < codes.length; i++) {
      edge = this.findEdge(node, codes[i])
      if (edge < 0) return -1
      node = this.edges[edge] >>> this.childShift
    }
    return edge
  }

  // Returns the edge index reached by spelling `word` (alphabet letters), or -1.
  walk(word) {
    let node = this.root
    let edge = -1
    for (let i = 0; i < word.length; i++) {
      const code = this.alphabet.indexOf(word.charAt(i))
      if (code < 0) return -1
      edge = this.findEdge(node, code)
      if (edge < 0) return -1
      node = this.edges[edge] >>> this.childShift
    }
    return edge
  }

  contains(word) {
    if (!word) return false
    const edge = this.walk(word)
    return edge >= 0 && (this.edges[edge] & this.terminalBit) !== 0
  }

  // Frequency tier of `word`, or -1 if it is not a word.
  tierOf(word) {
    if (!word) return -1
    const edge = this.walk(word)
    if (edge < 0 || !(this.edges[edge] & this.terminalBit)) return -1
    return (this.edges[edge] >>> this.tierShift) & this.tierMask
  }
}
