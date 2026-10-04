// The bundled open French lexicon.
//
// Compiled from Grammalecte's "Lexique des formes fléchies du français"
// (MPL-2.0) by tools/build-dictionary.mjs with dictionary/policies/open-fr.json.
// It is NOT the Officiel du Scrabble: it misses words the ODS accepts and
// accepts words the ODS does not. isOfficial() is false whatever the data
// file's header says, and the UI always labels it "Français — Open Lexicon".

import { DawgDictionaryProvider } from "./provider.mjs"

export const OPEN_FRENCH_ID = "open-fr"

export class OpenFrenchDictionaryProvider extends DawgDictionaryProvider {
  constructor(dawg, options) {
    const header = dawg && dawg.header ? dawg.header : {}
    if (header.id !== OPEN_FRENCH_ID) throw new Error("not the open French lexicon (id " + header.id + ")")
    if (header.language !== "fr") throw new Error("open French lexicon must be French")
    super(dawg, {
      id: OPEN_FRENCH_ID,
      name: "Français — Open Lexicon",
      shortName: "Open Lexicon",
      language: "fr",
      version: header.dataVersion || "",
      official: false,
      forms: options && options.forms
    })
    this.source = header.source || null
  }

  isOfficial() { return false }
}
