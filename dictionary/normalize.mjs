// Word normalization and lexical policy.
//
// French Scrabble tiles carry no accents: ÉTÉ is played with E, T, E, and a
// cedilla or a diaeresis is simply not on the tile. The tile spelling of a
// word is therefore its "folded" form, and that is what the board, the move
// validator and the AI work with. The accented spelling is kept separately,
// for display only (see DictionaryProvider.lookup).
//
// Folding is deliberately narrow. Only the diacritics and ligatures of French
// orthography are folded; any other character (ñ, ø, å, a hyphen, an
// apostrophe, a digit…) makes the whole entry unplayable instead of being
// stripped. Stripping would quietly turn foreign or compound spellings into
// tile words that no French lexicon contains — the opposite of what a
// validator is for.
//
// This module is shared by the runtime and by tools/build-dictionary.mjs, so
// the dictionary is compiled with exactly the rules the game checks with.

export const TILE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

// Lowercase and uppercase forms of every French diacritic and ligature.
export const FRENCH_FOLDS = Object.freeze({
  "à": "A", "â": "A", "ä": "A",
  "é": "E", "è": "E", "ê": "E", "ë": "E",
  "î": "I", "ï": "I",
  "ô": "O", "ö": "O",
  "ù": "U", "û": "U", "ü": "U",
  "ÿ": "Y",
  "ç": "C",
  "œ": "OE", "æ": "AE",
  "À": "A", "Â": "A", "Ä": "A",
  "É": "E", "È": "E", "Ê": "E", "Ë": "E",
  "Î": "I", "Ï": "I",
  "Ô": "O", "Ö": "O",
  "Ù": "U", "Û": "U", "Ü": "U",
  "Ÿ": "Y",
  "Ç": "C",
  "Œ": "OE", "Æ": "AE"
})

// The lowercase letters a display form may contain, in a fixed order. The
// display-form DAWG encodes letters as indexes into this string, so changing
// the order invalidates compiled data (bump the data format version).
export const DISPLAY_ALPHABET = "abcdefghijklmnopqrstuvwxyzàâäéèêëîïôöùûüÿçœæ"

export const DEFAULT_POLICY = Object.freeze({
  id: "fr-fold-strict",
  folds: "fr",
  minLength: 2,
  maxLength: 15
})

// Folds `text` to tile letters, or returns null when the text holds a
// character the policy cannot represent. Length limits are not applied here;
// see isPlayableForm.
export function foldWord(text) {
  const s = String(text == null ? "" : text)
  let out = ""
  for (let i = 0; i < s.length; i++) {
    const ch = s.charAt(i)
    const code = s.charCodeAt(i)
    if (code >= 65 && code <= 90) { out += ch; continue }           // A-Z
    if (code >= 97 && code <= 122) { out += ch.toUpperCase(); continue } // a-z
    const folded = FRENCH_FOLDS[ch]
    if (folded === undefined) return null
    out += folded
  }
  return out
}

export function isPlayableForm(folded, policy) {
  const p = policy || DEFAULT_POLICY
  if (typeof folded !== "string") return false
  if (folded.length < p.minLength || folded.length > p.maxLength) return false
  for (let i = 0; i < folded.length; i++) {
    const code = folded.charCodeAt(i)
    if (code < 65 || code > 90) return false
  }
  return true
}

// Normalizes a word for a dictionary query: folds it and enforces the policy.
// Returns null for anything that cannot be a playable word.
export function normalizeQuery(text, policy) {
  const folded = foldWord(text)
  if (folded === null) return null
  return isPlayableForm(folded, policy) ? folded : null
}

// Normalizes a display (accented) form: lowercase, every character inside the
// display alphabet. Returns null otherwise.
export function normalizeDisplayForm(text) {
  const s = String(text == null ? "" : text).toLowerCase()
  if (s.length === 0) return null
  for (let i = 0; i < s.length; i++) {
    if (DISPLAY_ALPHABET.indexOf(s.charAt(i)) === -1) return null
  }
  return s
}

export function letterIndex(letter) {
  const code = String(letter).charCodeAt(0)
  return code >= 65 && code <= 90 ? code - 65 : -1
}
