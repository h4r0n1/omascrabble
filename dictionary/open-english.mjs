// The bundled open English word list.
//
// Compiled from SCOWL (Kevin Atkinson and contributors, MIT-like licence) by
// tools/build-dictionary.mjs with dictionary/policies/open-en.json. It is
// neither TWL nor Collins Scrabble Words, and isOfficial() is always false.

import { DawgDictionaryProvider } from "./provider.mjs"

export const OPEN_ENGLISH_ID = "open-en"

export class OpenEnglishDictionaryProvider extends DawgDictionaryProvider {
  constructor(dawg, options) {
    const header = dawg && dawg.header ? dawg.header : {}
    if (header.id !== OPEN_ENGLISH_ID) throw new Error("not the open English word list (id " + header.id + ")")
    if (header.language !== "en") throw new Error("open English word list must be English")
    super(dawg, {
      id: OPEN_ENGLISH_ID,
      name: "English — Open Word List",
      shortName: "Open Word List",
      language: "en",
      version: header.dataVersion || "",
      official: false,
      forms: options && options.forms
    })
  }

  isOfficial() { return false }
}
