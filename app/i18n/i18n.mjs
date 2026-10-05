// Interface translations. Catalogs map keys to strings with {placeholders},
// or to functions when grammar needs logic (elision, plurals, persons).
//
//   t("en", "status.yourTurn")                     → "Your turn"
//   t("fr", "status.yourTurn")                     → "Votre tour"
//
// Lookup order: the requested language, then English (the default), then the
// key itself, so a missing string is visible rather than blank.
// The interface language is independent of the game language (tiles and
// dictionary): an English interface can host a French game and vice versa.

import { FR } from "./fr.mjs"
import { EN } from "./en.mjs"

export const CATALOGS = Object.freeze({ fr: FR, en: EN })
export const INTERFACE_LANGUAGES = Object.freeze(["fr", "en"])
export const DEFAULT_LANGUAGE = "en"

function interpolate(text, args) {
  if (!args) return text
  return text.replace(/\{(\w+)\}/g, function(m, name) {
    return args[name] === undefined || args[name] === null ? m : String(args[name])
  })
}

export function t(lang, key, args) {
  const catalog = CATALOGS[lang] || CATALOGS[DEFAULT_LANGUAGE]
  let entry = catalog[key]
  if (entry === undefined) entry = CATALOGS[DEFAULT_LANGUAGE][key]
  if (entry === undefined) return key
  if (typeof entry === "function") return entry(args || {})
  return interpolate(entry, args)
}

// "auto" follows the system locale (LANG): French for a French locale,
// English otherwise.
export function resolveLanguage(preference, locale) {
  if (INTERFACE_LANGUAGES.indexOf(preference) !== -1) return preference
  const l = String(locale || "").toLowerCase()
  if (l.indexOf("fr") === 0) return "fr"
  if (l.length > 0 && l !== "c" && l !== "posix") return "en"
  return DEFAULT_LANGUAGE
}

// Keys present in one catalog and missing in another (tests use this).
export function missingKeys() {
  const out = {}
  const all = new Set()
  for (const lang in CATALOGS) for (const k in CATALOGS[lang]) all.add(k)
  for (const lang in CATALOGS) {
    const missing = []
    all.forEach(function(k) { if (CATALOGS[lang][k] === undefined) missing.push(k) })
    if (missing.length) out[lang] = missing.sort()
  }
  return out
}
