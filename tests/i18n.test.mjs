import { t, missingKeys, resolveLanguage, CATALOGS } from "../app/i18n/i18n.mjs"
import { REASON } from "../engine/reasons.mjs"
import { SAVE_ERROR } from "../engine/serializer.mjs"
import { DIFFICULTIES, PERSONALITIES } from "../ai/difficulty.mjs"
import { SHORTCUT_ACTIONS } from "../app/settings.mjs"
import { DICTIONARIES } from "../dictionary/registry.mjs"
import { MODE } from "../engine/game.mjs"

export const name = "I18n"

export function register(tt) {
  tt.test("every key exists in every language", function() {
    tt.deepEqual(missingKeys(), {})
  })

  tt.test("every code the engine can return has a string", function() {
    const needed = []
    for (const k in REASON) needed.push("reason." + REASON[k])
    for (const k in SAVE_ERROR) needed.push("save." + SAVE_ERROR[k])
    for (const d of DIFFICULTIES) needed.push("difficulty." + d, "setup.difficulty." + d + ".detail")
    for (const p in PERSONALITIES) needed.push("personality." + p)
    for (const a of SHORTCUT_ACTIONS) needed.push("shortcut." + a)
    for (const k in MODE) needed.push("mode." + MODE[k])
    for (const d of DICTIONARIES) needed.push("dict." + d.id + ".label", "dict." + d.id + ".note")
    for (const p of ["TRIPLE_WORD", "DOUBLE_WORD", "TRIPLE_LETTER", "DOUBLE_LETTER"]) needed.push("premium." + p, "premium.name." + p)
    for (const lang in CATALOGS) for (const key of needed) tt.ok(CATALOGS[lang][key] !== undefined, lang + " lacks " + key)
  })

  tt.test("interpolation, plurals and grammar", function() {
    tt.equal(t("fr", "common.tilesInBag", { n: 1 }), "1 lettre dans le sac")
    tt.equal(t("fr", "common.tilesInBag", { n: 12 }), "12 lettres dans le sac")
    tt.equal(t("en", "common.tilesInBag", { n: 1 }), "1 tile in the bag")
    tt.equal(t("en", "common.tilesInBag", { n: 0 }), "0 tiles in the bag")
    tt.equal(t("fr", "end.winsNamed", { name: "Anne" }), "Victoire d’Anne")
    tt.equal(t("fr", "end.winsNamed", { name: "Paul" }), "Victoire de Paul")
    tt.equal(t("en", "end.winsNamed", { name: "Paul" }), "Paul wins")
    tt.equal(t("fr", "reason.INVALID_WORD", { words: ["MOX"] }), "Mot invalide : MOX")
    tt.equal(t("en", "reason.INVALID_CROSS_WORD", { words: ["QI", "XU"] }), "Invalid cross word: QI, XU")
    tt.equal(t("en", "premium.TRIPLE_WORD"), "TW")
    tt.equal(t("fr", "premium.TRIPLE_WORD"), "MT")
  })

  tt.test("fallbacks never show a blank", function() {
    tt.equal(t("xx", "status.yourTurn"), "Your turn", "unknown language falls back to English")
    tt.equal(t("en", "no.such.key"), "no.such.key")
  })

  tt.test("language resolution", function() {
    tt.equal(resolveLanguage("en", "fr_FR"), "en")
    tt.equal(resolveLanguage("auto", "fr_SN"), "fr")
    tt.equal(resolveLanguage("auto", "en_US"), "en")
    tt.equal(resolveLanguage("auto", "de_DE"), "en")
    tt.equal(resolveLanguage("auto", "C"), "en")
    tt.equal(resolveLanguage("bogus", ""), "en")
  })
}
