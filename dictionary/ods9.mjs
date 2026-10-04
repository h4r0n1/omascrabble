// Provider for L'Officiel du Scrabble, 9th edition (ODS 9), the official
// French Scrabble reference for 2024–2027.
//
// No ODS data ships with this project: the electronic word list is licensed.
// Someone who holds a licence can compile it into the game's format —
//
//   node tools/build-dictionary.mjs --policy dictionary/policies/ods9.example.json \
//        --source <licensed word list> --format wordlist \
//        --out ~/.local/share/omascrabble/dictionaries
//
// — and the game offers "Français — ODS 9 · Officiel" once the file is
// there. Nothing else changes: scoring, the board, the AI and the UI only see
// the DictionaryProvider interface.

import { DawgDictionaryProvider } from "./provider.mjs"

export const ODS9_ID = "ods9"

export class ODS9DictionaryProvider extends DawgDictionaryProvider {
  constructor(dawg, options) {
    const header = dawg && dawg.header ? dawg.header : {}
    if (header.id !== ODS9_ID) throw new Error("not an ODS 9 dictionary (id " + header.id + ")")
    if (header.language !== "fr") throw new Error("ODS 9 must be French")
    super(dawg, {
      id: ODS9_ID,
      name: "Français — ODS 9",
      shortName: "ODS 9",
      language: "fr",
      version: header.dataVersion || "",
      official: header.official === true,
      forms: options && options.forms
    })
  }
}
