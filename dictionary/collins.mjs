// Slot for Collins Scrabble Words, the licensed English list used in most
// countries outside North America. Nothing is bundled: with a licence,
// compile the list into ~/.local/share/omascrabble/dictionaries/collins.dawg
// (id "collins", language "en", "official": true) and it appears under New
// game. Same contract as the ODS 9 slot.

import { DawgDictionaryProvider } from "./provider.mjs"

export const COLLINS_ID = "collins"

export class CollinsDictionaryProvider extends DawgDictionaryProvider {
  constructor(dawg, options) {
    const header = dawg && dawg.header ? dawg.header : {}
    if (header.id !== COLLINS_ID) throw new Error("not a Collins dictionary (id " + header.id + ")")
    if (header.language !== "en") throw new Error("Collins must be English")
    super(dawg, {
      id: COLLINS_ID,
      name: "English — Collins Scrabble Words",
      shortName: "Collins",
      language: "en",
      version: header.dataVersion || "",
      official: header.official === true,
      forms: options && options.forms
    })
  }
}
