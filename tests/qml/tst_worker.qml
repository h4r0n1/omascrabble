import QtQuick
import QtTest
import "../../engine/game.mjs" as Game

// The AI worker in a real WorkerScript thread: loads the dictionary, answers
// a think request with a legal action, and reports errors as messages.
TestCase {
  name: "Worker"

  WorkerScript {
    id: worker
    source: "../../ai/worker.mjs"
    property var replies: []
    onMessage: function(m) { var r = replies.slice(); r.push(m); replies = r }
  }

  function readFixture(rel) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl("../../" + rel), false)
    xhr.send()
    return xhr.responseText
  }

  function waitFor(type, requestId) {
    var found = null
    tryVerify(function() {
      for (var i = 0; i < worker.replies.length; i++) {
        var m = worker.replies[i]
        if ((m.type === type || m.type === "error") && (requestId === undefined || m.requestId === requestId)) { found = m; return true }
      }
      return false
    }, 20000)
    return found
  }

  function test_worker_round_trip() {
    tryVerify(function() { return worker.ready }, 5000)
    worker.sendMessage({ type: "init", dictId: "open-fr", text: readFixture("dictionary/data/open-fr.dawg") })
    var ready = waitFor("ready")
    compare(ready.type, "ready", ready.message)
    verify(ready.words > 400000)

    var state = Game.createGame({ mode: "human_vs_ai", seed: 4, firstPlayer: 1, players: [{ name: "Vous", kind: "human" }, { name: "IA", kind: "ai", difficulty: "expert" }] })
    worker.sendMessage({ type: "think", requestId: 7, view: Game.publicView(state, 1), difficulty: "expert", seed: 1, budgetMs: 2000 })
    var action = waitFor("action", 7)
    compare(action.type, "action", action.message)
    // The worker's answer is an ordinary engine action, validated as such
    // (no dictionary passed: the opening must still be structurally legal).
    var applied = Game.applyAction(state, action.action, {})
    verify(applied.ok || applied.reason === "DICTIONARY_UNAVAILABLE", applied.message)
    console.log("AI chose:", JSON.stringify(action.info))

    worker.sendMessage({ type: "think", requestId: 8, view: null, difficulty: "expert" })
    var err = waitFor("error", 8)
    compare(err.type, "error")
    compare(err.stage, "think")
  }
}
