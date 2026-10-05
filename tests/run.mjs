#!/usr/bin/env node
// Node test runner: `node tests/run.mjs [filter]`.
// Loads the bundled dictionary as a fixture when it exists.

import { readFileSync, existsSync, readdirSync, statSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { createRunner } from "./lib/harness.mjs"
import { SUITES } from "./all.mjs"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const read = function(rel) {
  const p = join(root, rel)
  return existsSync(p) ? readFileSync(p, "utf8") : null
}

// Every QML file the plugin ships (static checks).
function qmlSources(dir, out) {
  for (const name of readdirSync(join(root, dir))) {
    const rel = dir ? dir + "/" + name : name
    if (name.startsWith(".") || rel === "dev" || rel === "tests" || rel === "tools") continue
    if (statSync(join(root, rel)).isDirectory()) qmlSources(rel, out)
    else if (name.endsWith(".qml")) out[rel] = readFileSync(join(root, rel), "utf8")
  }
  return out
}

const context = {
  qmlSources: qmlSources("", {}),
  openLexicon: read("dictionary/data/open-fr.dawg"),
  openLexiconForms: read("dictionary/data/open-fr.forms.dawg"),
  openEnglish: read("dictionary/data/open-en.dawg"),
  openEnglishForms: read("dictionary/data/open-en.forms.dawg")
}

const runner = createRunner(context)
for (const suite of SUITES) runner.add(suite)
const started = Date.now()
const results = runner.run(process.argv[2])
for (const line of results.log) console.log(line)
console.log(results.passed + " passed, " + results.failed + " failed, " + results.skipped + " skipped (" + (Date.now() - started) + " ms)")
process.exit(results.failed ? 1 : 0)
