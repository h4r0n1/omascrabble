import { foldWord, normalizeQuery, normalizeDisplayForm, TILE_ALPHABET, DISPLAY_ALPHABET } from "../dictionary/normalize.mjs"
import { decodeDawg, DawgLoader, DawgError, checksumEdges, Dawg } from "../dictionary/dawg.mjs"
import { buildDawg, DawgBuilder } from "../dictionary/dawg-builder.mjs"
import { displayFormsFor, DawgDictionaryProvider, DictionaryProvider } from "../dictionary/provider.mjs"
import { OpenFrenchDictionaryProvider } from "../dictionary/open-french.mjs"
import { ODS9DictionaryProvider } from "../dictionary/ods9.mjs"
import { createProvider, DICTIONARIES } from "../dictionary/registry.mjs"

export const name = "Dictionary"

// Encodes a Dawg the way the build tool does, without Node's Buffer.
function encode(dawg, extraHeader) {
  const edges = dawg.edges
  const bytes = []
  for (let i = 0; i < edges.length; i++) {
    const v = edges[i]
    bytes.push(v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255)
  }
  const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let out = ""
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i], b = bytes[i + 1], c = bytes[i + 2]
    out += B64.charAt(a >> 2) + B64.charAt(((a & 3) << 4) | ((b === undefined ? 0 : b) >> 4))
    out += b === undefined ? "=" : B64.charAt(((b & 15) << 2) | ((c === undefined ? 0 : c) >> 6))
    out += c === undefined ? "=" : B64.charAt(c & 63)
  }
  const header = Object.assign({}, dawg.header, { checksum: checksumEdges(edges) }, extraHeader || {})
  return JSON.stringify(header) + "\n" + out + "\n"
}

export function register(t) {
  t.test("folding keeps French letters and refuses the rest", function() {
    t.equal(foldWord("été"), "ETE")
    t.equal(foldWord("Cœur"), "COEUR")
    t.equal(foldWord("ex-æquo"), null)
    t.equal(foldWord("cañon"), null, "ñ is not stripped into N")
    t.equal(foldWord("aujourd’hui"), null)
    t.equal(foldWord("naïf"), "NAIF")
    t.equal(foldWord("ÇA"), "CA")
    t.equal(normalizeQuery("été"), "ETE")
    t.equal(normalizeQuery("a"), null, "below the minimum length")
    t.equal(normalizeQuery("ANTICONSTITUTIONNELLEMENT"), null, "longer than the board")
    t.equal(normalizeDisplayForm("Été"), "été")
    t.equal(normalizeDisplayForm("señor"), null)
  })

  t.test("DAWG build and lookup", function() {
    const words = ["MAISON", "MAISONS", "MAIS", "MAI", "QI", "ZOO", "ZOOS"]
    const d = buildDawg(words, TILE_ALPHABET, { tierBits: 2, tierOf: function(w) { return w.length % 4 } })
    for (const w of words) t.ok(d.contains(w), w)
    t.ok(!d.contains("MAISO"))
    t.ok(!d.contains("MA"))
    t.ok(!d.contains(""))
    t.ok(!d.contains("QIS"))
    t.equal(d.tierOf("MAISON"), 2)
    t.equal(d.tierOf("ZOOS"), 0)
    t.equal(d.tierOf("XYZ"), -1)
    t.throws(function() { const b = new DawgBuilder(TILE_ALPHABET); b.insert([1, 2], 0); b.insert([0], 0) })
  })

  t.test("encoded DAWG round-trips, incrementally too", function() {
    const words = ["ABAT", "ABATS", "BAS", "BAT", "TABAC"]
    const text = encode(buildDawg(words, TILE_ALPHABET, { tierBits: 2 }))
    const d = decodeDawg(text)
    for (const w of words) t.ok(d.contains(w))
    const loader = new DawgLoader(text)
    let steps = 0
    while (!loader.step(8)) steps++
    t.ok(steps > 2, "work was sliced")
    t.ok(loader.dawg.contains("TABAC"))
    t.equal(loader.progress, 1)
  })

  t.test("corrupt dictionary data is rejected", function() {
    const good = encode(buildDawg(["ABAT", "ABATS", "BAS"], TILE_ALPHABET, { tierBits: 2 }))
    const nl = good.indexOf("\n")
    const header = JSON.parse(good.slice(0, nl))
    const payload = good.slice(nl + 1).trim()
    const codeOf = function(text) {
      try { decodeDawg(text); return "OK" } catch (e) { return e instanceof DawgError ? e.code : "OTHER:" + e.message }
    }
    t.equal(codeOf(good), "OK")
    t.equal(codeOf(""), "EMPTY")
    t.equal(codeOf("garbage"), "NO_HEADER")
    t.equal(codeOf("{not json}\nAAAA"), "BAD_HEADER")
    t.equal(codeOf(JSON.stringify(Object.assign({}, header, { format: "zip" })) + "\n" + payload), "BAD_FORMAT")
    t.equal(codeOf(JSON.stringify(Object.assign({}, header, { version: 9 })) + "\n" + payload), "BAD_VERSION")
    t.equal(codeOf(JSON.stringify(Object.assign({}, header, { checksum: "00000000" })) + "\n" + payload), "BAD_CHECKSUM")
    t.equal(codeOf(JSON.stringify(header) + "\n" + payload.slice(0, 8)), "TRUNCATED")
    t.equal(codeOf(JSON.stringify(header) + "\n" + "!" + payload.slice(1)), "BAD_PAYLOAD")
    t.equal(codeOf(JSON.stringify(Object.assign({}, header, { words: header.words + 1 })) + "\n" + payload), "BAD_STRUCTURE")
  })

  t.test("a backward child pointer (a cycle) is rejected", function() {
    const d = buildDawg(["AB", "ABC"], TILE_ALPHABET, { tierBits: 0 })
    const edges = Uint32Array.from(d.edges)
    // point the last edge back at the root
    const last = edges.length - 1
    edges[last] = ((edges[last] & ((1 << d.childShift) - 1)) | (1 << d.childShift)) >>> 0
    const header = Object.assign({}, d.header, { checksum: checksumEdges(edges) })
    let code = ""
    try { new Dawg(edges, header) } catch (e) { code = e.code }
    t.equal(code, "BAD_STRUCTURE")
  })

  t.test("display forms restore French spelling", function() {
    const forms = buildDawg(["été", "ou", "où", "cœur", "coeur", "tête", "tète"], DISPLAY_ALPHABET, {})
    t.deepEqual(displayFormsFor(forms, "ETE"), ["été"])
    t.deepEqual(displayFormsFor(forms, "OU").sort(), ["ou", "où"])
    t.deepEqual(displayFormsFor(forms, "COEUR").sort(), ["coeur", "cœur"])
    t.deepEqual(displayFormsFor(forms, "TETE").sort(), ["tète", "tête"])
    t.deepEqual(displayFormsFor(forms, "XYZ"), [])
  })

  t.test("provider contract", function() {
    const graph = buildDawg(["ETE", "COEUR", "QI"], TILE_ALPHABET, { tierBits: 2 })
    const forms = buildDawg(["été", "cœur", "qi"], DISPLAY_ALPHABET, {})
    const p = new DawgDictionaryProvider(graph, { id: "x", name: "X", language: "fr", version: "1", forms: forms })
    t.ok(p instanceof DictionaryProvider)
    t.ok(p.isValid("ETE"))
    t.ok(p.isValid("été"), "accented input is folded")
    t.ok(!p.isValid("ET"))
    t.ok(!p.isValid("señor"))
    const l = p.lookup("cœur")
    t.equal(l.word, "COEUR")
    t.equal(l.valid, true)
    t.deepEqual(l.displayForms, ["cœur"])
    t.equal(p.lookup("??").valid, false)
    t.deepEqual(p.describe(), { id: "x", name: "X", shortName: "X", language: "fr", version: "1", official: false })
  })

  t.test("open lexicon is never official; ODS 9 slot needs its own data", function() {
    const graph = buildDawg(["ETE"], TILE_ALPHABET, { tierBits: 2 })
    graph.header.id = "open-fr"
    graph.header.language = "fr"
    graph.header.official = true // a lying header changes nothing
    const open = new OpenFrenchDictionaryProvider(graph)
    t.equal(open.isOfficial(), false)
    t.equal(open.name(), "Français — Open Lexicon")
    t.throws(function() { new ODS9DictionaryProvider(graph) })
    const ods = buildDawg(["ETE"], TILE_ALPHABET, { tierBits: 2 })
    ods.header.id = "ods9"
    ods.header.language = "fr"
    ods.header.official = true
    const official = createProvider("ods9", ods)
    t.equal(official.isOfficial(), true)
    t.equal(official.name(), "Français — ODS 9")
    // One bundled open list per language; licensed lists are never bundled.
    const bundled = DICTIONARIES.filter(function(d) { return d.location === "bundled" })
    t.deepEqual(bundled.map(function(d) { return d.language }).sort(), ["en", "fr"])
    t.ok(bundled.every(function(d) { return !d.official }))
    t.ok(DICTIONARIES.filter(function(d) { return d.official }).every(function(d) { return d.location === "user" }))
  })

  t.test("bundled open lexicon (real data)", function(ctx) {
    if (!ctx.openLexicon) t.skip("dictionary data not provided")
    const d = decodeDawg(ctx.openLexicon)
    const forms = ctx.openLexiconForms ? decodeDawg(ctx.openLexiconForms) : null
    const p = createProvider("open-fr", d, forms)
    t.equal(p.isOfficial(), false)
    t.ok(d.wordCount > 400000, "about 407k words, got " + d.wordCount)
    for (const w of ["MAISON", "MAISONS", "QI", "ETE", "COEUR", "JOUER", "ZYTHUM", "WAGONNETS", "KIWIS"])
      t.ok(p.isValid(w), w + " should be valid")
    for (const w of ["XQZ", "MAISONE", "AUJOURDHUIX", "KM", "CM", "MARSEILLE", "DAKAR", "SENEGAL"])
      t.ok(!p.isValid(w), w + " should be invalid")
    if (forms) t.ok(p.lookup("ETE").displayForms.indexOf("été") !== -1)
    t.ok(p.tierOf("MAISON") >= 2, "maison is common")
  })

  t.test("bundled open English list (real data)", function(ctx) {
    if (!ctx.openEnglish) t.skip("dictionary data not provided")
    const d = decodeDawg(ctx.openEnglish)
    const forms = ctx.openEnglishForms ? decodeDawg(ctx.openEnglishForms) : null
    const p = createProvider("open-en", d, forms)
    t.equal(p.isOfficial(), false)
    t.equal(p.language(), "en")
    t.ok(d.wordCount > 200000, "about 246k words, got " + d.wordCount)
    for (const w of ["HOUSE", "HOUSES", "QI", "QAT", "ZA", "XU", "QUIZ", "COLOUR", "COLOR", "JEEZ", "CAFE", "NAIVE"])
      t.ok(p.isValid(w), w + " should be valid")
    for (const w of ["XQZ", "TOKYO", "LONDON", "BS", "MS", "HOUSEZ"])
      t.ok(!p.isValid(w), w + " should be invalid")
    if (forms) t.ok(p.lookup("CAFE").displayForms.indexOf("café") !== -1)
    t.ok(p.tierOf("HOUSE") === 3, "house is common")
    t.throws(function() { createProvider("collins", d) }, "the open list can't pose as Collins")
  })
}
