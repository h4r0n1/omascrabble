// CandidateGenerator: keeps the best few moves while the generator streams
// every legal one, so memory stays flat no matter how many moves exist.
//
// The visitor sees each move as it is found and scores it with a cheap key
// (score, plus the leave when the profile values it). Only moves that make
// the cut are materialized; the expensive judgement (board danger, look-ahead)
// runs afterwards on this short list.

import { leaveValue } from "./evaluator.mjs"

export class CandidateCollector {
  // keyOf(gen) → number; limit = how many to keep.
  constructor(limit, keyOf) {
    this.limit = Math.max(1, limit)
    this.keyOf = keyOf
    this.items = []      // sorted descending by key
    this.total = 0
  }

  onMove(gen) {
    this.total++
    const key = this.keyOf(gen)
    const items = this.items
    if (items.length >= this.limit && key <= items[items.length - 1].key) return
    const move = gen.materialize()
    move.leave = Int8Array.from(gen.rack)
    let i = items.length
    while (i > 0 && items[i - 1].key < key) i--
    items.splice(i, 0, { key: key, move: move })
    if (items.length > this.limit) items.pop()
  }

  moves() {
    return this.items.map(function(it) { return it.move })
  }
}

// The stage-one key for a profile.
export function keyFunction(profile, options) {
  const leaveWeight = options && options.bagEmpty ? 0 : profile.leaveWeight
  const language = options && options.language
  const shortBias = profile.maxTilesPreferred < 7
  return function(gen) {
    let key = gen.score
    if (leaveWeight > 0) key += leaveWeight * leaveValue(gen.rack, language)
    if (shortBias && gen.tilesUsed > profile.maxTilesPreferred) key -= 12 * (gen.tilesUsed - profile.maxTilesPreferred)
    return key
  }
}
