// WorkerScript entry: the AI and other heavy dictionary work run here, on a
// thread of their own, so the shell's UI thread never waits on a search.
//
// Messages in (all carry a `type`):
//   init       { dictId, text }                  decode the tile dictionary
//   forms      { text }                          decode accented spellings
//   think      { requestId, view, difficulty, personality, thinkingScale, seed, budgetMs }
//   challenge  { requestId, words, difficulty, seed }
//   hint       { requestId, view, count }
//   lookup     { requestId, words }
// Messages out: ready, formsReady, action, challengeDecision, hints, lookup,
// error { requestId, stage, message }. Every handler is wrapped: a failure is
// reported back as a message, never thrown into the host.

import { decodeDawg } from "../dictionary/dawg.mjs"
import { createProvider } from "../dictionary/registry.mjs"
import { displayFormsFor } from "../dictionary/provider.mjs"
import { chooseAction, decideChallenge, topMoves } from "./player.mjs"
import { profileFor } from "./difficulty.mjs"

let provider = null
let forms = null
let dictId = ""

function reply(message) {
  WorkerScript.sendMessage(message)
}

function fail(msg, stage, e) {
  reply({ type: "error", requestId: msg && msg.requestId !== undefined ? msg.requestId : -1, stage: stage, message: e && e.message ? String(e.message) : String(e) })
}

const handlers = {
  init: function(msg) {
    const started = Date.now()
    const graph = decodeDawg(String(msg.text || ""))
    provider = createProvider(String(msg.dictId), graph, forms)
    dictId = String(msg.dictId)
    reply({ type: "ready", dictId: dictId, words: graph.wordCount, ms: Date.now() - started })
  },

  forms: function(msg) {
    forms = decodeDawg(String(msg.text || ""))
    if (provider && typeof provider.attachDisplayForms === "function") provider.attachDisplayForms(forms)
    reply({ type: "formsReady", forms: forms.wordCount })
  },

  think: function(msg) {
    if (!provider) throw new Error("dictionary not loaded")
    const profile = profileFor(msg.difficulty, { personality: msg.personality, thinkingScale: msg.thinkingScale })
    const budget = Number.isFinite(msg.budgetMs) ? msg.budgetMs : profile.thinkMs[1]
    const result = chooseAction(msg.view, profile, provider.graph(), { seed: msg.seed, deadline: Date.now() + budget })
    reply({ type: "action", requestId: msg.requestId, action: result.action, info: result.info, minMs: profile.thinkMs[0] })
  },

  challenge: function(msg) {
    if (!provider) throw new Error("dictionary not loaded")
    const words = Array.isArray(msg.words) ? msg.words.map(String) : []
    reply({ type: "challengeDecision", requestId: msg.requestId, challenge: decideChallenge(words, msg.difficulty, provider, { seed: msg.seed }) })
  },

  hint: function(msg) {
    if (!provider) throw new Error("dictionary not loaded")
    reply({ type: "hints", requestId: msg.requestId, moves: topMoves(msg.view, provider.graph(), msg.count || 5) })
  },

  lookup: function(msg) {
    const out = {}
    const words = Array.isArray(msg.words) ? msg.words.slice(0, 64) : []
    for (const w of words) out[String(w)] = forms ? displayFormsFor(forms, String(w), 6) : []
    reply({ type: "lookup", requestId: msg.requestId, results: out })
  }
}

WorkerScript.onMessage = function(msg) {
  const handler = msg && handlers[msg.type]
  if (!handler) { fail(msg, "dispatch", "unknown message " + (msg && msg.type)); return }
  try {
    handler(msg)
  } catch (e) {
    fail(msg, msg.type, e)
  }
}
