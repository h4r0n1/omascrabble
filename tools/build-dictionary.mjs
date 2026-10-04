#!/usr/bin/env node
// Compiles an open French lexicon into the game's dictionary files.
//
//   node tools/build-dictionary.mjs --source path/to/lexique-grammalecte-fr-v7.7.zip
//   node tools/build-dictionary.mjs --download
//
// Options:
//   --policy <file>   lexical policy (default dictionary/policies/open-fr.json)
//   --source <file>   the Grammalecte lexicon, .zip or extracted .txt
//   --download        fetch the archive named in the policy into tools/.cache/
//   --out <dir>       output directory (default dictionary/data)
//
// Outputs <id>.dawg (tile spellings + frequency tiers, used for play) and
// <id>.forms.dawg (accented spellings, used only to display words), and
// prints a summary. Build-time only: needs Node 18+, nothing else.

import { createHash } from "node:crypto"
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { inflateRawSync } from "node:zlib"
import { DawgBuilder, encodeDawgFile } from "./dawg-builder.mjs"
import { TILE_ALPHABET, DISPLAY_ALPHABET, foldWord, isPlayableForm, normalizeDisplayForm } from "../dictionary/normalize.mjs"
import { decodeDawg } from "../dictionary/dawg.mjs"

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..")

function parseArgs(argv) {
  const args = { policy: join(ROOT, "dictionary/policies/open-fr.json"), out: join(ROOT, "dictionary/data") }
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i]
    if (a === "--policy") args.policy = resolve(argv[++i])
    else if (a === "--source") args.source = resolve(argv[++i])
    else if (a === "--out") args.out = resolve(argv[++i])
    else if (a === "--download") args.download = true
    else if (a === "-h" || a === "--help") args.help = true
    else throw new Error("unknown argument: " + a)
  }
  return args
}

// Minimal ZIP reader: finds `name` through the central directory and
// inflates it. Enough for the single-file Grammalecte archive.
function readZipEntry(buf, name) {
  let eocd = -1
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break }
  }
  if (eocd < 0) throw new Error("not a zip archive")
  const count = buf.readUInt16LE(eocd + 10)
  let p = buf.readUInt32LE(eocd + 16)
  for (let n = 0; n < count; n++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error("corrupt zip central directory")
    const method = buf.readUInt16LE(p + 10)
    const compSize = buf.readUInt32LE(p + 20)
    const nameLen = buf.readUInt16LE(p + 28)
    const extraLen = buf.readUInt16LE(p + 30)
    const commentLen = buf.readUInt16LE(p + 32)
    const localOffset = buf.readUInt32LE(p + 42)
    const entryName = buf.toString("utf8", p + 46, p + 46 + nameLen)
    if (entryName === name) {
      const lNameLen = buf.readUInt16LE(localOffset + 26)
      const lExtraLen = buf.readUInt16LE(localOffset + 28)
      const dataStart = localOffset + 30 + lNameLen + lExtraLen
      const data = buf.subarray(dataStart, dataStart + compSize)
      if (method === 0) return data
      if (method === 8) return inflateRawSync(data)
      throw new Error("unsupported zip compression method " + method)
    }
    p += 46 + nameLen + extraLen + commentLen
  }
  throw new Error("entry not found in archive: " + name)
}

async function loadSource(args, policy) {
  let path = args.source
  if (args.download) {
    const cacheDir = join(ROOT, "tools/.cache")
    mkdirSync(cacheDir, { recursive: true })
    path = join(cacheDir, policy.source.url.split("/").pop())
    if (!existsSync(path)) {
      console.error("Downloading " + policy.source.url)
      const res = await fetch(policy.source.url)
      if (!res.ok) throw new Error("download failed: HTTP " + res.status)
      writeFileSync(path, Buffer.from(await res.arrayBuffer()))
    }
  }
  if (!path) throw new Error("pass --source <file> or --download")
  const raw = readFileSync(path)
  const sha256 = createHash("sha256").update(raw).digest("hex")
  if (policy.source.sha256 && path.endsWith(".zip") && policy.source.sha256 !== sha256)
    throw new Error("source checksum mismatch: expected " + policy.source.sha256 + ", got " + sha256)
  const text = path.endsWith(".zip") ? readZipEntry(raw, policy.source.file).toString("utf8") : raw.toString("utf8")
  return { text, sha256, path }
}

function tierFor(word, index, tiers) {
  const thresholds = tiers.thresholds
  const short = tiers.shortWordPenalty
  if (short && word.length <= short.maxLength) index -= short.penalty
  let tier = 0
  for (let i = 0; i < thresholds.length; i++) if (index >= thresholds[i]) tier = i + 1
  return tier
}

function rowRejection(row, lp) {
  const tags = row.tags
  for (const t of tags) {
    if (lp.excludeTags.indexOf(t) !== -1) return "tag:" + t
    for (const prefix of lp.excludeTagPrefixes) if (t.indexOf(prefix) === 0) return "tag:" + prefix
  }
  for (const n of row.notes) if (lp.excludeNotes.indexOf(n) !== -1) return "note:" + n
  if (lp.subDictionaries !== "all") {
    const parts = row.subdict.split("/")
    if (!parts.some(function(p) { return lp.subDictionaries.indexOf(p) !== -1 })) return "subdict"
  }
  if (lp.excludeLowercaseMismatch && row.form !== row.form.toLowerCase()) return "capitalised"
  return null
}

function parseLexicon(text) {
  const lines = text.split("\n")
  let header = null
  const rows = []
  for (const line of lines) {
    if (!header) {
      if (line.indexOf("id\tfid\t") === 0) header = line.split("\t")
      continue
    }
    if (!line) continue
    const parts = line.split("\t")
    if (parts.length < header.length) continue
    const get = function(name) { return parts[header.indexOf(name)] || "" }
    rows.push({
      form: get("Flexion"),
      tags: get("Étiquettes").split(/\s+/).filter(Boolean),
      notes: get("Notes").split(/\s+/).filter(Boolean),
      subdict: get("Sous-dictionnaire"),
      freq: parseInt(get("Indice de fréquence"), 10) || 0
    })
  }
  if (!header) throw new Error("lexicon header row not found")
  return rows
}

// Sorts words by their code sequence under `alphabet`.
function sortByAlphabet(words, alphabet) {
  const keyed = words.map(function(w) {
    let key = ""
    for (let i = 0; i < w.length; i++) key += String.fromCharCode(48 + alphabet.indexOf(w.charAt(i)))
    return [key, w]
  })
  keyed.sort(function(a, b) { return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0 })
  return keyed.map(function(k) { return k[1] })
}

function codesOf(word, alphabet) {
  const out = new Array(word.length)
  for (let i = 0; i < word.length; i++) {
    const c = alphabet.indexOf(word.charAt(i))
    if (c < 0) throw new Error("letter outside alphabet: " + word)
    out[i] = c
  }
  return out
}

async function main() {
  const args = parseArgs(process.argv)
  if (args.help) {
    console.log(readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").slice(1, 15).join("\n"))
    return
  }
  const policy = JSON.parse(readFileSync(args.policy, "utf8"))
  const lp = policy.lexicalPolicy
  const source = await loadSource(args, policy)
  const rows = parseLexicon(source.text)

  const rejected = new Map()
  const reject = function(reason) { rejected.set(reason, (rejected.get(reason) || 0) + 1) }
  const tiles = new Map() // folded -> best frequency index
  const display = new Set()
  for (const row of rows) {
    const why = rowRejection(row, lp)
    if (why) { reject(why); continue }
    const folded = foldWord(row.form)
    if (folded === null) { reject("character"); continue }
    if (!isPlayableForm(folded, lp)) { reject("length"); continue }
    const shown = normalizeDisplayForm(row.form)
    if (shown === null) { reject("display-character"); continue }
    const prev = tiles.get(folded)
    if (prev === undefined || row.freq > prev) tiles.set(folded, row.freq)
    display.add(shown)
  }

  const tileWords = sortByAlphabet(Array.from(tiles.keys()), TILE_ALPHABET)
  const tileBuilder = new DawgBuilder(TILE_ALPHABET, { tierBits: 2 })
  const tierCounts = [0, 0, 0, 0]
  for (const w of tileWords) {
    const tier = tierFor(w, tiles.get(w), policy.frequencyTiers)
    tierCounts[tier]++
    tileBuilder.insert(codesOf(w, TILE_ALPHABET), tier)
  }
  const tilePacked = tileBuilder.finish()

  const displayWords = sortByAlphabet(Array.from(display), DISPLAY_ALPHABET)
  const displayBuilder = new DawgBuilder(DISPLAY_ALPHABET, { tierBits: 0 })
  for (const w of displayWords) displayBuilder.insert(codesOf(w, DISPLAY_ALPHABET), 0)
  const displayPacked = displayBuilder.finish()

  const meta = {
    id: policy.id,
    name: policy.name,
    shortName: policy.shortName,
    language: policy.language,
    official: policy.official === true,
    dataVersion: policy.source.version + "-" + createHash("sha256").update(JSON.stringify(policy)).digest("hex").slice(0, 8),
    source: {
      name: policy.source.name,
      author: policy.source.author,
      version: policy.source.version,
      url: policy.source.url,
      license: policy.source.license,
      sha256: source.sha256
    },
    lexicalPolicy: lp,
    frequencyTiers: { thresholds: policy.frequencyTiers.thresholds, shortWordPenalty: policy.frequencyTiers.shortWordPenalty || null }
  }

  mkdirSync(args.out, { recursive: true })
  const tileFile = encodeDawgFile(tilePacked, TILE_ALPHABET, 2, Object.assign({ kind: "tiles", tierCounts: tierCounts }, meta))
  const displayFile = encodeDawgFile(displayPacked, DISPLAY_ALPHABET, 0, Object.assign({ kind: "display" }, meta))
  // Round-trip through the runtime reader before writing anything.
  const check = decodeDawg(tileFile)
  for (const w of ["MAISON", "QI", "ETE", "COEUR"]) if (tiles.has(w) && !check.contains(w)) throw new Error("round-trip failed for " + w)
  decodeDawg(displayFile)
  writeFileSync(join(args.out, policy.id + ".dawg"), tileFile)
  writeFileSync(join(args.out, policy.id + ".forms.dawg"), displayFile)

  const byLength = {}
  for (const w of tileWords) byLength[w.length] = (byLength[w.length] || 0) + 1
  console.log(JSON.stringify({
    source: source.path,
    sourceSha256: source.sha256,
    rows: rows.length,
    playableWords: tileWords.length,
    displayForms: displayWords.length,
    tierCounts: tierCounts,
    byLength: byLength,
    tiles: { nodes: tilePacked.nodes, edges: tilePacked.edges.length, bytes: tileFile.length },
    display: { nodes: displayPacked.nodes, edges: displayPacked.edges.length, bytes: displayFile.length },
    rejected: Object.fromEntries(Array.from(rejected.entries()).sort(function(a, b) { return b[1] - a[1] }).slice(0, 20))
  }, null, 2))
}

main().catch(function(e) {
  console.error("build-dictionary: " + (e && e.message ? e.message : e))
  process.exit(1)
})
