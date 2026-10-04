// DictionaryProvider: the only way the game asks "is this a word?".
//
// The engine, the AI and the UI depend on this interface alone, never on a
// particular word list, so a licensed ODS provider (or another language) can
// be dropped in without touching scoring, the board, the AI or the UI.
//
//   isValid(word)  → boolean. `word` may be a tile spelling (ETE) or an
//                    accented one (été); both are folded by the lexical policy.
//   lookup(word)   → { query, word, valid, displayForms[], tier, official }
//   language()     → "fr"
//   name()         → "Français — Open Lexicon"
//   version()      → data version string
//   isOfficial()   → true only for a licensed official lexicon
//   tierOf(word)   → frequency tier 0..3 (AI vocabulary), -1 if not a word
//   graph()        → the tile-alphabet Dawg used for move generation

import { normalizeQuery, DEFAULT_POLICY, FRENCH_FOLDS, TILE_ALPHABET } from "./normalize.mjs"

export class DictionaryProvider {
  id() { return "" }
  name() { return "" }
  shortName() { return this.name() }
  language() { return "" }
  version() { return "" }
  isOfficial() { return false }
  policy() { return DEFAULT_POLICY }
  isValid(word) { return false }
  tierOf(word) { return -1 }
  graph() { return null }
  displayFormsOf(folded) { return [] }

  lookup(word) {
    const folded = normalizeQuery(word, this.policy())
    if (folded === null) return { query: String(word), word: null, valid: false, displayForms: [], tier: -1, official: this.isOfficial() }
    const valid = this.isValid(folded)
    return {
      query: String(word),
      word: folded,
      valid: valid,
      displayForms: valid ? this.displayFormsOf(folded) : [],
      tier: valid ? this.tierOf(folded) : -1,
      official: this.isOfficial()
    }
  }

  describe() {
    return { id: this.id(), name: this.name(), shortName: this.shortName(), language: this.language(), version: this.version(), official: this.isOfficial() }
  }
}

function foldLetter(ch) {
  const code = ch.charCodeAt(0)
  if (code >= 97 && code <= 122) return ch.toUpperCase()
  return FRENCH_FOLDS[ch] || null
}

// Enumerates the accented spellings in `forms` (a display-alphabet Dawg)
// whose tile spelling is `folded`. Bounded by the query length; returns at
// most `limit` forms.
export function displayFormsFor(forms, folded, limit) {
  const max = limit || 8
  const out = []
  if (!forms || !folded) return out
  const alphabet = forms.alphabet
  const folds = []
  for (let i = 0; i < alphabet.length; i++) folds.push(foldLetter(alphabet.charAt(i)))
  const edges = forms.edges
  function visit(node, pos, prefix) {
    if (out.length >= max || node <= 0) return
    for (let i = node; ; i++) {
      const e = edges[i]
      const f = folds[e & forms.letterMask]
      if (f && folded.substr(pos, f.length) === f) {
        const nextPos = pos + f.length
        const spelled = prefix + alphabet.charAt(e & forms.letterMask)
        if (nextPos === folded.length) {
          if (e & forms.terminalBit) out.push(spelled)
        } else {
          visit(e >>> forms.childShift, nextPos, spelled)
        }
        if (out.length >= max) return
      }
      if (e & forms.lastBit) break
    }
  }
  visit(forms.root, 0, "")
  return out
}

// A provider backed by compiled DAWGs. `forms` (accented spellings) is
// optional and may be attached later; without it lookup() still answers,
// with no display forms.
export class DawgDictionaryProvider extends DictionaryProvider {
  constructor(dawg, options) {
    super()
    if (!dawg || dawg.alphabet !== TILE_ALPHABET) throw new Error("dictionary graph must use the tile alphabet")
    const header = dawg.header || {}
    this._dawg = dawg
    this._forms = (options && options.forms) || null
    this._id = String((options && options.id) || header.id || "")
    this._name = String((options && options.name) || header.name || this._id)
    this._shortName = String((options && options.shortName) || header.shortName || this._name)
    this._language = String((options && options.language) || header.language || "")
    this._version = String((options && options.version) || header.dataVersion || "")
    this._official = !!(options && options.official)
    const lp = header.lexicalPolicy || {}
    this._policy = {
      id: DEFAULT_POLICY.id,
      folds: DEFAULT_POLICY.folds,
      minLength: Number.isInteger(lp.minLength) ? lp.minLength : DEFAULT_POLICY.minLength,
      maxLength: Number.isInteger(lp.maxLength) ? lp.maxLength : DEFAULT_POLICY.maxLength
    }
  }

  id() { return this._id }
  name() { return this._name }
  shortName() { return this._shortName }
  language() { return this._language }
  version() { return this._version }
  isOfficial() { return this._official }
  policy() { return this._policy }
  graph() { return this._dawg }
  attachDisplayForms(forms) { this._forms = forms || null }
  hasDisplayForms() { return this._forms !== null }

  isValid(word) {
    const folded = normalizeQuery(word, this._policy)
    return folded !== null && this._dawg.contains(folded)
  }

  tierOf(word) {
    const folded = normalizeQuery(word, this._policy)
    return folded === null ? -1 : this._dawg.tierOf(folded)
  }

  displayFormsOf(folded) {
    return this._forms ? displayFormsFor(this._forms, folded, 8) : []
  }
}

// A plain word-list provider for tests and tools. It builds no graph unless
// one is passed, so it cannot drive the AI on its own.
export class MemoryDictionaryProvider extends DictionaryProvider {
  constructor(words, options) {
    super()
    this._words = new Set()
    for (const w of words || []) {
      const f = normalizeQuery(w, DEFAULT_POLICY)
      if (f !== null) this._words.add(f)
    }
    this._graph = (options && options.graph) || null
    this._name = (options && options.name) || "Liste de test"
    this._official = !!(options && options.official)
  }
  id() { return "memory" }
  name() { return this._name }
  language() { return "fr" }
  version() { return "test" }
  isOfficial() { return this._official }
  graph() { return this._graph }
  isValid(word) {
    const f = normalizeQuery(word, DEFAULT_POLICY)
    return f !== null && this._words.has(f)
  }
  tierOf(word) { return this.isValid(word) ? 3 : -1 }
}
