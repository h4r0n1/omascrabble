// Move generation benchmark on the real lexicon. Runs under Node; the same
// module is imported by dev/bench-movegen.qml for Qt's engine.
import { decodeDawg } from "../dictionary/dawg.mjs"
import { MoveGenerator, boardArrays, rackCounts } from "../ai/movegen.mjs"
import { createGame, applyAction, publicView } from "../engine/game.mjs"
import { createProvider } from "../dictionary/registry.mjs"

const VALUES = [1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 10, 1, 2, 1, 1, 3, 8, 1, 1, 1, 1, 4, 10, 10, 10, 10]

export function runBench(dictText, log) {
  const graph = decodeDawg(dictText)
  const dict = createProvider("open-fr", graph)
  const gen = new MoveGenerator(graph, VALUES)
  // Build a mid-game position by greedy self-play.
  let s = createGame({ mode: "human_vs_human", players: [{ name: "A" }, { name: "B" }], seed: 9, dictionary: dict.describe() })
  for (let turn = 0; turn < 10 && s.status === "active"; turn++) {
    const view = publicView(s, s.current)
    const a = boardArrays(view.board)
    let best = null
    gen.generate(a.board, a.blanks, rackCounts(view.rack), {}, { onMove: function(g) { if (!best || g.score > best.score) best = g.materialize() } })
    if (!best) { s = applyAction(s, { type: "pass", player: s.current }, {}).state; continue }
    const rack = s.players[s.current].rack.slice()
    const placements = best.tiles.map(function(t) {
      const i = rack.findIndex(function(id) { return s.tiles[id].letter === (t.blank ? "?" : t.letter) })
      const id = rack.splice(i, 1)[0]
      return t.blank ? { tileId: id, row: t.row, col: t.col, jokerLetter: t.letter } : { tileId: id, row: t.row, col: t.col }
    })
    s = applyAction(s, { type: "play", player: s.current, placements: placements }, { dictionary: dict }).state
  }
  const view = publicView(s, s.current)
  const a = boardArrays(view.board)
  const racks = { "7 letters": "ERSATIN", "1 joker": "ERSAT?N", "2 jokers": "ERS??IN", "heavy": "KWYZXQJ" }
  for (const label in racks) {
    const counts = new Int8Array(27)
    for (const ch of racks[label]) counts[ch === "?" ? 26 : ch.charCodeAt(0) - 65]++
    let n = 0, top = 0
    const t0 = Date.now()
    gen.generate(a.board, a.blanks, counts, {}, { onMove: function(g) { n++; if (g.score > top) top = g.score } })
    log(label + ": " + n + " moves, best " + top + ", " + (Date.now() - t0) + " ms, nodes " + gen.nodesVisited)
  }
}
