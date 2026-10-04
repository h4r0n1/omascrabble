import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugin/app"
import "plugin/components"
import "plugin/ai/player.mjs" as AI
import "plugin/engine/game.mjs" as Engine

// Offscreen preview harness: renders the real game UI with the real Omarchy
// theme tokens and saves a PNG. Driven by dev/preview.sh; never touches the
// running shell (separate process, temporary XDG_STATE_HOME).
ShellRoot {
  id: rootShell

  readonly property string scenario: Quickshell.env("PREVIEW_SCENARIO") || "midgame"
  readonly property string output: Quickshell.env("PREVIEW_OUTPUT") || "/tmp/preview.png"
  readonly property int w: Number(Quickshell.env("PREVIEW_WIDTH") || 1180)
  readonly property int h: Number(Quickshell.env("PREVIEW_HEIGHT") || 860)
  readonly property string themeName: Quickshell.env("PREVIEW_THEME") || ""
  readonly property string appearance: Quickshell.env("PREVIEW_APPEARANCE") || ""
  readonly property string pluginDir: Quickshell.env("PREVIEW_PLUGIN") || ""

  FileView {
    id: themeColors
    path: rootShell.themeName !== "" ? "/usr/share/omarchy/themes/" + rootShell.themeName + "/colors.toml" : ""
    printErrors: false
    onLoaded: Color.loadColors(text())
  }

  FloatingWindow {
    id: win
    implicitWidth: rootShell.w
    implicitHeight: rootShell.h
    color: Color.background

    Item {
      id: content
      anchors.fill: parent

      App {
        id: app
        pluginDir: rootShell.pluginDir
        windowVisible: true
      }

      GameView {
        id: view
        anchors.fill: parent
        controller: app.controller
        saves: app.saves
        dictionary: app.dictionary
        sounds: app.sounds
        systemPrefersDark: app.preferences.prefersDark
      }
    }
  }

  property int step: 0

  function placePending(letters) {
    var c = app.controller
    var rack = c.rackTiles
    var placed = 0
    // find an anchor next to existing tiles: try row 8 from col 3 to the right
    for (var r = 0; r < 15 && placed === 0; r++) {
      for (var col = 0; col < 15 && placed === 0; col++) {
        if (c.boardTileAt(r, col) !== null) continue
        var hasNeighbor = (r > 0 && c.boardTileAt(r - 1, col) !== null) || (r < 14 && c.boardTileAt(r + 1, col) !== null)
        if (!hasNeighbor) continue
        for (var k = 0; k < Math.min(letters, rack.length); k++) {
          if (col + k > 14 || c.boardTileAt(r, col + k) !== null) break
          var t = rack[k]
          c.placeTile(t.id, r, col + k, t.isJoker ? "E" : null)
          placed++
        }
      }
    }
  }

  // AI self-play on the main thread to reach a mid-game position quickly.
  function selfPlay(moves) {
    var c = app.controller
    for (var i = 0; i < moves && c.isActive; i++) {
      var p = c.game.current
      var choice = AI.chooseAction(Engine.publicView(c.game, p), "expert", app.dictionary.provider.graph(), { seed: 40 + i, deadline: Date.now() + 200 })
      var res = Engine.applyAction(c.game, choice.action, { dictionary: app.dictionary.provider })
      if (!res.ok) break
      c.game = res.state
      c.syncRackOrder()
      var last = null
      for (var e = 0; e < res.events.length; e++) if (res.events[e].type === "play") last = res.events[e]
      if (last) c.lastCommitted = { player: last.player, moveIndex: last.moveIndex, score: last.score, bingo: last.bingo, words: c.game.moves[last.moveIndex].words }
    }
    c.revision++
  }

  // End-to-end: the human plays the worker's hint, the AI answers through
  // its worker thread; prints the state at each stage.
  property string flowStage: "start"
  property int flowWait: 0
  function shot() {
    content.grabToImage(function(result) {
      result.saveToFile(rootShell.output)
      console.log("PREVIEW_SAVED " + rootShell.output)
      Qt.quit()
    })
  }
  // Keyboard-only play through the real key handler: Tab to the board, type
  // the hint word letter by letter, Enter.
  function key(k, text, mods) {
    var e = { key: k, text: text || "", modifiers: mods || 0, accepted: false }
    var handled = view.handleGameKey(e)
    if (handled) view.keyboardMode = true
    return handled
  }
  function runKeys() {
    var c = app.controller
    flowWait++
    if (flowWait > 300) { console.log("KEYS TIMEOUT " + flowStage); shot(); flowStage = "done"; return }
    if (flowStage === "start") {
      if (!app.dictionary.workerReady) return
      c.requestHint()
      flowStage = "hint"
      return
    }
    if (flowStage === "hint") {
      if (!c.hintMove) return
      var m = c.hintMove
      c.hintMove = null
      console.log("KEYS target " + m.word + " " + m.dir + " at " + m.row + "," + m.col + " score " + m.score)
      key(Qt.Key_Tab)                                   // rack → board
      view.boardCursor = { row: m.row, col: m.col }
      key(m.dir === "H" ? Qt.Key_Right : Qt.Key_Down)   // sets the typing direction
      key(m.dir === "H" ? Qt.Key_Left : Qt.Key_Up)      // back to the start square
      for (var i = 0; i < m.word.length; i++) {
        var ch = m.word.charAt(i)
        var handled = key(0x41 + ch.charCodeAt(0) - 65, ch.toLowerCase())
        if (!handled) console.log("KEYS letter not handled " + ch)
      }
      console.log("KEYS pending " + c.pending.length + " preview " + (c.preview ? c.preview.mainWord + " " + c.preview.score + " valid=" + c.preview.valid : "none"))
      key(Qt.Key_Escape)
      console.log("KEYS after Escape pending=" + c.pending.length)
      for (var j = 0; j < m.word.length; j++) key(0x41 + m.word.charCodeAt(j) - 65, m.word.charAt(j).toLowerCase())
      key(Qt.Key_Backspace)
      console.log("KEYS after Backspace pending=" + c.pending.length)
      key(0x41 + m.word.charCodeAt(m.word.length - 1) - 65, m.word.charAt(m.word.length - 1).toLowerCase())
      key(Qt.Key_Return)
      console.log("KEYS after Enter " + c.statusJson())
      flowStage = "waitAi"
      return
    }
    if (flowStage === "waitAi") {
      if (c.aiThinking || c.game.current !== 0) return
      console.log("KEYS AI answered: " + c.game.moves[c.game.moves.length - 1].mainWord)
      key(Qt.Key_Tab); key(Qt.Key_Tab)                  // board → controls
      console.log("KEYS zone " + view.keyZone + " control " + view.controlIndex)
      flowStage = "settle"
      flowWait = 0
      return
    }
    if (flowStage === "settle" && flowWait > 8) { flowStage = "done"; shot() }
  }

  function runFlow() {
    var c = app.controller
    flowWait++
    if (flowWait > 300) { console.log("FLOW TIMEOUT at " + flowStage + " " + c.statusJson()); shot(); flowStage = "done"; return }
    if (flowStage === "start") {
      if (!app.dictionary.workerReady) return
      if (rootShell.scenario === "challenge-ai") {
        // A phony on the first move, under challenge rules: the expert AI must contest it.
        var rack = c.rackTiles
        c.placeTile(rack[0].id, 7, 7, rack[0].isJoker ? "Q" : null)
        c.placeTile(rack[1].id, 7, 8, rack[1].isJoker ? "Q" : null)
        c.placeTile(rack[2].id, 7, 9, rack[2].isJoker ? "Q" : null)
        console.log("FLOW phony preview " + JSON.stringify(c.preview ? c.preview.formedWords : null))
        c.confirmMove()
        flowStage = "waitAi"
        return
      }
      c.requestHint()
      flowStage = "hint"
      return
    }
    if (flowStage === "hint") {
      if (!c.hintMove) return
      console.log("FLOW hint " + c.hintMove.word + " " + c.hintMove.score)
      var placements = c.hintMove.placements
      for (var i = 0; i < placements.length; i++) c.placeTile(placements[i].tileId, placements[i].row, placements[i].col, placements[i].jokerLetter || null)
      console.log("FLOW preview valid=" + c.preview.valid + " score=" + c.preview.score)
      c.confirmMove()
      console.log("FLOW after human " + c.statusJson())
      flowStage = "waitAi"
      return
    }
    if (flowStage === "waitAi") {
      if (c.aiThinking || c.game.current !== 0) return
      console.log("FLOW after AI " + c.statusJson())
      if (c.challengeOutcome) console.log("FLOW challenge " + JSON.stringify(c.challengeOutcome))
      var last = c.game.moves[c.game.moves.length - 1]
      console.log("FLOW last move " + JSON.stringify({ type: last.type, word: last.mainWord, score: last.score, player: last.player }))
      flowStage = "settle"
      flowWait = 0
      return
    }
    if (flowStage === "settle" && flowWait > 12) { flowStage = "done"; shot() }
  }

  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      var c = app.controller
      if (rootShell.step === 0) {
        if (rootShell.appearance !== "") app.saves.saveSettings(Object.assign({}, app.saves.settings, { appearance: rootShell.appearance }))
        if (app.dictionary.status !== "ready" || !app.saves.ready) return
        rootShell.step = 1
        var sc = rootShell.scenario
        if (sc === "home") { view.screen = "home"; return }
        if (sc === "setup") { view.screen = "setup"; return }
        var mode = sc === "practice" ? "practice" : sc === "hvh" ? "human_vs_human" : "human_vs_ai"
        c.newGame({ mode: mode, difficulty: "expert", timeMinutes: 20, dictionary: "open-fr", validation: sc === "challenge" || sc === "challenge-ai" ? "challenge" : "immediate", firstPlayer: "human" })
        view.showGame()
        if (sc === "start" || sc === "flow" || sc === "challenge-ai" || sc === "keys") return
        rootShell.selfPlay(sc === "end" ? 80 : 12)
        if (sc === "pending" || sc === "midgame" || sc === "narrow") rootShell.placePending(3)
        if (sc === "settings") view.overlay = "settings"
        if (sc === "stats") view.overlay = "stats"
        if (sc === "end") { if (c.isActive) c.resign() }
        if (sc === "joker") c.jokerRequest = { tileId: 0, row: 0, col: 0 }
        if (sc === "exchange") view.openExchange()
        return
      }
      if (rootShell.scenario === "keys") { rootShell.runKeys(); return }
      if (rootShell.scenario === "flow" || rootShell.scenario === "challenge-ai") {
        rootShell.runFlow()
        return
      }
      rootShell.step++
      if (rootShell.step === 14) {
        content.grabToImage(function(result) {
          result.saveToFile(rootShell.output)
          console.log("PREVIEW_SAVED " + rootShell.output)
          Qt.quit()
        })
      }
    }
  }
}
