// Known dictionaries and where their data lives. The QML DictionaryService
// reads the files (it owns file IO); this module only describes them and
// turns decoded graphs into providers.
//
// Paths: `file`/`formsFile` are relative to the plugin directory for bundled
// data, or to the user dictionary directory
// ($XDG_DATA_HOME/omascrabble/dictionaries) for installed data.

import { OpenFrenchDictionaryProvider, OPEN_FRENCH_ID } from "./open-french.mjs"
import { ODS9DictionaryProvider, ODS9_ID } from "./ods9.mjs"
import { OpenEnglishDictionaryProvider, OPEN_ENGLISH_ID } from "./open-english.mjs"
import { CollinsDictionaryProvider, COLLINS_ID } from "./collins.mjs"

export const DICTIONARIES = Object.freeze([
  Object.freeze({
    id: OPEN_FRENCH_ID,
    language: "fr",
    tileset: "fr-classic",
    official: false,
    location: "bundled",
    file: "dictionary/data/open-fr.dawg",
    formsFile: "dictionary/data/open-fr.forms.dawg",
    // label and note: interface catalogs, "dict.<id>.label" / ".note"
  }),
  Object.freeze({
    id: ODS9_ID,
    language: "fr",
    tileset: "fr-classic",
    official: true,
    location: "user",
    file: "ods9.dawg",
    formsFile: "ods9.forms.dawg",
    // licensed, never bundled
  }),
  Object.freeze({
    id: OPEN_ENGLISH_ID,
    language: "en",
    tileset: "en-classic",
    official: false,
    location: "bundled",
    file: "dictionary/data/open-en.dawg",
    formsFile: "dictionary/data/open-en.forms.dawg"
  }),
  Object.freeze({
    id: COLLINS_ID,
    language: "en",
    tileset: "en-classic",
    official: true,
    location: "user",
    file: "collins.dawg",
    formsFile: "collins.forms.dawg"
    // licensed, never bundled
  })
])

export const DEFAULT_DICTIONARY_ID = OPEN_FRENCH_ID

export function dictionaryEntry(id) {
  for (const d of DICTIONARIES) if (d.id === id) return d
  return null
}

// The open dictionary of a game language.
export function defaultDictionaryFor(language) {
  return language === "en" ? OPEN_ENGLISH_ID : OPEN_FRENCH_ID
}

export function createProvider(id, dawg, forms) {
  if (id === OPEN_FRENCH_ID) return new OpenFrenchDictionaryProvider(dawg, { forms: forms })
  if (id === ODS9_ID) return new ODS9DictionaryProvider(dawg, { forms: forms })
  if (id === OPEN_ENGLISH_ID) return new OpenEnglishDictionaryProvider(dawg, { forms: forms })
  if (id === COLLINS_ID) return new CollinsDictionaryProvider(dawg, { forms: forms })
  throw new Error("unknown dictionary: " + id)
}
