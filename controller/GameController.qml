import QtQuick
import "../engine/game.mjs" as Engine
import "../engine/board.mjs" as BoardModel
import "../engine/notation.mjs" as Notation
import "../engine/rules.mjs" as Rules
import "../ai/difficulty.mjs" as Difficulty

// GameController: the bridge between the UI and the GameEngine.
//
// It owns the authoritative engine state (`game`) and the UI-only state
// around it — tiles placed but not yet played (`pending`), rack order,
// selection, previews — and it orchestrates the AI worker, clocks,
// challenges and persistence. It never decides a rule: legality, scores and
// turn order always come from the engine, and every engine call is guarded
// so a bug surfaces as a message, never as a broken shell.
QtObject {
  id: ctl

  // Collaborators, set by the view.
  property var dictionary: null   // DictionaryService
  property var saves: null        // SaveManager
  property var worker: null       // WorkerScript hosting the AI
  property var settings: saves ? saves.settings : ({})
  property bool windowActive: true

  // Engine state and UI state around it.
  property var game: null
  property int revision: 0
  property var pending: []          // [{ tileId, row, col, jokerLetter }]
  property var rackOrder: ({})      // { "<player>": [tileId, …] }
  property int selectedTileId: -1
  property var preview: null        // validation result for `pending`
  property var hoverCell: null      // { row, col }
  property var hoverPreview: null
  property var jokerRequest: null   // { tileId, row, col } while the letter picker is open
  property int highlightMove: -1    // move index highlighted from the history
  property int replayIndex: -1      // >= 0: the board shows the position after that move
  property var hintMove: null       // { tiles, word, score } ghost shown on the board
  property var hints: []
  property var bestMoveReveal: null // practice: best move of the position just played
  property var practiceTop: null
  property bool aiThinking: false
  property var aiInfo: null
  property var lastCommitted: null  // { player, moveIndex, score, words, bingo }
  property var challengeOutcome: null
  property var displayForms: ({})   // word → accented spellings (async lookups)
  property bool handoverPending: false
  property string notice: ""
  property string noticeKind: "info"
  property var endSummary: null
  property bool confirmRequested: false

  property double turnStartedAt: Date.now()
  property double clockNow: Date.now()
  property int requestSerial: 0
  property int aiRequestId: -1
  property int hintRequestId: -1
  property var queuedAiAction: null
  property bool waitingForWorker: false

  // Derived.
  readonly property bool hasGame: game !== null
  readonly property bool isOver: game !== null && game.status === "ended"
  readonly property bool isActive: game !== null && game.status === "active"
  readonly property int current: game ? game.current : 0
  readonly property int viewer: viewerIndex(game)
  readonly property bool humanTurn: isActive && game.players[game.current].kind === "human" && game.current === viewer && !handoverPending
  readonly property var provider: dictionary ? dictionary.provider : null
  readonly property bool dictionaryReady: provider !== null
  readonly property var legal: { revision; return game ? Engine.legalActions(game, viewer) : ({}) }
  readonly property bool clockEnabled: game !== null && game.rules.time.totalMs > 0
  readonly property var cells: { revision; return buildCells() }
  readonly property var rackTiles: { revision; return buildRack() }
  readonly property var moveList: { revision; return buildMoveList() }
  readonly property int bagCount: { revision; return game ? game.bag.length : 0 }

  signal moveCommitted(var events, var result, int player)
  signal moveRejected(string message, var result)
  signal gameStarted()
  signal gameEnded(var end)
  signal tilePlaced(int row, int col)
  signal tileLifted()
  signal challengeResolved(var outcome)
  signal jokerLetterNeeded()

  // ------------------------------------------------------------ helpers

  function viewerIndex(g) {
    if (!g) return 0
    if (g.mode === "human_vs_human") return g.current
    for (var i = 0; i < g.players.length; i++) if (g.players[i].kind === "human") return i
    return 0
  }

  function say(message, kind) {
    notice = String(message || "")
    noticeKind = kind || "info"
    noticeTimer.restart()
  }

  function guard(label, fn, fallback) {
    try {
      return fn()
    } catch (e) {
      console.warn("omarchy-scrabble: " + label + " failed:", e && e.stack ? e.stack : e)
      say("Une erreur inattendue est survenue (" + label + "). La partie est intacte.", "error")
      return fallback
    }
  }

  function tile(id) { return game ? game.tiles[id] : null }

  function pendingAt(row, col) {
    for (var i = 0; i < pending.length; i++) if (pending[i].row === row && pending[i].col === col) return pending[i]
    return null
  }

  function isPending(tileId) {
    for (var i = 0; i < pending.length; i++) if (pending[i].tileId === tileId) return true
    return false
  }

  function boardTileAt(row, col) {
    if (!game) return null
    var id = game.board[row * 15 + col]
    return id === null || id === undefined ? null : id
  }

  function lastPlayMove() {
    if (!game) return null
    for (var i = game.moves.length - 1; i >= 0; i--) {
      var m = game.moves[i]
      if (m.type === "play" && !m.withdrawn) return m
    }
    return null
  }

  // Per-cell primitives for the board. Delegates bind to plain values, so a
  // change only repaints the cells whose values actually changed.
  // The board after `index` moves, rebuilt from the move records.
  function replayCells(index) {
    var out = new Array(225)
    for (var i = 0; i < 225; i++) out[i] = { letter: "", points: 0, joker: false, kind: "empty", last: false, highlight: false, invalid: false, tileId: -1 }
    if (!game) return out
    for (var m = 0; m <= index && m < game.moves.length; m++) {
      var move = game.moves[m]
      if (move.type !== "play") continue
      // A withdrawn move stood until its challenge, which comes later.
      var withdrawnBy = -1
      if (move.withdrawn) for (var k = m + 1; k < game.moves.length; k++) if (game.moves[k].type === "challenge" && game.moves[k].target === m) { withdrawnBy = k; break }
      if (move.withdrawn && withdrawnBy !== -1 && withdrawnBy <= index) continue
      for (var p = 0; p < move.placements.length; p++) {
        var pl = move.placements[p]
        var t = game.tiles[pl.tileId]
        out[pl.row * 15 + pl.col] = { letter: pl.letter, points: t.points, joker: t.isJoker, kind: "board", last: false, highlight: m === index, invalid: false, tileId: pl.tileId }
      }
    }
    return out
  }

  function buildCells() {
    if (replayIndex >= 0) return replayCells(replayIndex)
    var out = new Array(225)
    var lastMove = lastPlayMove()
    var lastSet = {}
    if (lastMove) for (var i = 0; i < lastMove.placements.length; i++) lastSet[lastMove.placements[i].row * 15 + lastMove.placements[i].col] = true
    var hl = {}
    if (game && highlightMove >= 0 && highlightMove < game.moves.length) {
      var hm = game.moves[highlightMove]
      if (hm.type === "play") for (var h = 0; h < hm.placements.length; h++) hl[hm.placements[h].row * 15 + hm.placements[h].col] = true
    }
    var pend = {}
    for (var p = 0; p < pending.length; p++) pend[pending[p].row * 15 + pending[p].col] = pending[p]
    var hint = {}
    if (hintMove) for (var k = 0; k < hintMove.tiles.length; k++) hint[hintMove.tiles[k].row * 15 + hintMove.tiles[k].col] = hintMove.tiles[k]
    var invalid = {}
    if (preview && preview.words && preview.invalidWords && preview.invalidWords.length) {
      for (var w = 0; w < preview.words.length; w++) {
        if (preview.words[w].valid === false) for (var c = 0; c < preview.words[w].cells.length; c++) invalid[preview.words[w].cells[c].row * 15 + preview.words[w].cells[c].col] = true
      }
    }
    for (var idx = 0; idx < 225; idx++) {
      var cell = { letter: "", points: 0, joker: false, kind: "empty", last: false, highlight: false, invalid: !!invalid[idx], tileId: -1 }
      var id = game ? game.board[idx] : null
      if (id !== null && id !== undefined) {
        var t = game.tiles[id]
        cell.kind = "board"
        cell.tileId = id
        cell.joker = t.isJoker
        cell.letter = t.isJoker ? (game.jokerLetters[id] || "?") : t.letter
        cell.points = t.points
        cell.last = !!lastSet[idx]
        cell.highlight = !!hl[idx]
      } else if (pend[idx]) {
        var pt = game.tiles[pend[idx].tileId]
        cell.kind = "pending"
        cell.tileId = pt.id
        cell.joker = pt.isJoker
        cell.letter = pt.isJoker ? (pend[idx].jokerLetter || "?") : pt.letter
        cell.points = pt.points
      } else if (hint[idx]) {
        cell.kind = "hint"
        cell.letter = hint[idx].letter
        cell.joker = hint[idx].blank
      }
      out[idx] = cell
    }
    return out
  }

  // The viewer's rack in display order, without the tiles on the board.
  function buildRack() {
    if (!game) return []
    var order = rackOrder[String(viewer)] || game.players[viewer].rack
    var out = []
    for (var i = 0; i < order.length; i++) {
      var id = order[i]
      if (game.players[viewer].rack.indexOf(id) === -1 || isPending(id)) continue
      out.push(game.tiles[id])
    }
    return out
  }

  // Keeps each rack's display order across turns: tiles still on the rack
  // keep their slot, new tiles fill the slots that were played from.
  function syncRackOrder() {
    if (!game) return
    var next = {}
    for (var p = 0; p < game.players.length; p++) {
      var rack = game.players[p].rack
      var prev = rackOrder[String(p)] || []
      var slots = prev.map(function(id) { return rack.indexOf(id) !== -1 ? id : null })
      var fresh = rack.filter(function(id) { return prev.indexOf(id) === -1 })
      for (var s = 0; s < slots.length && fresh.length; s++) if (slots[s] === null) slots[s] = fresh.shift()
      next[String(p)] = slots.filter(function(id) { return id !== null }).concat(fresh)
    }
    rackOrder = next
  }

  function buildMoveList() {
    if (!game) return []
    var out = []
    var n = 0
    for (var i = 0; i < game.moves.length; i++) {
      var m = game.moves[i]
      var entry = { index: i, player: m.player, type: m.type, score: m.score, number: 0, text: "", position: "", withdrawn: !!m.withdrawn, bingo: !!m.bingo }
      if (m.type === "play") {
        n++
        entry.number = n
        var main = m.words[0]
        entry.text = main ? main.notation || main.word : ""
        entry.position = m.position
        entry.extra = m.words.length > 1 ? m.words.slice(1).map(function(w) { return w.notation || w.word }).join(", ") : ""
      } else if (m.type === "pass") {
        entry.text = "Passe"
      } else if (m.type === "exchange") {
        entry.text = "Échange (" + m.count + ")"
      } else if (m.type === "challenge") {
        entry.text = m.success ? "Contestation réussie" : "Contestation refusée"
        if (m.penalty && m.penalty.type === "points") entry.score = -m.penalty.points
      } else if (m.type === "resign") {
        entry.text = "Abandon"
      } else if (m.type === "timeout") {
        entry.text = "Temps écoulé"
      }
      out.push(entry)
    }
    return out
  }

  function remainingMs(player) {
    if (!clockEnabled) return 0
    var used = game.players[player].timeUsedMs
    if (isActive && player === game.current && !(settings.gameplay && settings.gameplay.pauseClockWhenHidden && !windowActive && game.players[player].kind === "human"))
      used += Math.max(0, clockNow - turnStartedAt)
    return game.rules.time.totalMs - used
  }

  function playerLabel(index) {
    if (!game) return ""
    return game.players[index].name
  }

  function difficultyLabel(index) {
    if (!game || game.players[index].kind !== "ai") return ""
    return Difficulty.DIFFICULTY_LABELS[game.players[index].difficulty] || ""
  }

  // ------------------------------------------------------------ previews

  function refreshPreview() {
    if (!game || pending.length === 0) { preview = null; revision++; return }
    var checkWords = !!(settings.gameplay && settings.gameplay.showWordValidation)
      && game.rules.validation === Rules.VALIDATION.IMMEDIATE && dictionaryReady
    preview = guard("aperçu", function() {
      return Engine.previewMove(game, viewer, pending, provider, { checkWords: checkWords })
    }, null)
    revision++
  }

  function setHover(row, col) {
    if (row < 0) { hoverCell = null; hoverPreview = null; return }
    hoverCell = { row: row, col: col }
    if (selectedTileId < 0 || !humanTurn || boardTileAt(row, col) !== null || pendingAt(row, col)) { hoverPreview = null; return }
    var t = tile(selectedTileId)
    if (!t || t.isJoker) { hoverPreview = null; return }
    var trial = pending.filter(function(p) { return p.tileId !== selectedTileId }).concat([{ tileId: selectedTileId, row: row, col: col }])
    var checkWords = !!(settings.gameplay && settings.gameplay.showWordValidation)
      && game.rules.validation === Rules.VALIDATION.IMMEDIATE && dictionaryReady
    hoverPreview = guard("survol", function() { return Engine.previewMove(game, viewer, trial, provider, { checkWords: checkWords }) }, null)
  }

  // Can the selected tile go to (row, col)? Used for the subtle error state.
  function placementProblem(row, col) {
    if (!game || boardTileAt(row, col) !== null) return "occupied"
    if (pending.length === 0) return ""
    var all = pending.filter(function(p) { return p.tileId !== selectedTileId })
    if (all.length === 0) return ""
    var sameRow = all.every(function(p) { return p.row === row })
    var sameCol = all.every(function(p) { return p.col === col })
    return sameRow || sameCol ? "" : "line"
  }

  // ------------------------------------------------------- placing tiles

  function selectTile(tileId) {
    if (!humanTurn) return
    selectedTileId = selectedTileId === tileId ? -1 : tileId
    if (selectedTileId >= 0) tileLifted()
    hoverPreview = null
  }

  function placeTile(tileId, row, col, jokerLetter) {
    if (!humanTurn || !game) return false
    if (row < 0 || col < 0 || row > 14 || col > 14) return false
    if (boardTileAt(row, col) !== null) return false
    var occupant = pendingAt(row, col)
    if (occupant && occupant.tileId !== tileId) return false
    if (game.players[viewer].rack.indexOf(tileId) === -1) return false
    var t = tile(tileId)
    var existing = null
    for (var i = 0; i < pending.length; i++) if (pending[i].tileId === tileId) existing = pending[i]
    var letter = jokerLetter || (existing ? existing.jokerLetter : null)
    if (t.isJoker && !letter) {
      jokerRequest = { tileId: tileId, row: row, col: col }
      jokerLetterNeeded()
      return true
    }
    var next = pending.filter(function(p) { return p.tileId !== tileId })
    next.push(t.isJoker ? { tileId: tileId, row: row, col: col, jokerLetter: letter } : { tileId: tileId, row: row, col: col })
    pending = next
    selectedTileId = -1
    hintMove = null
    hoverPreview = null
    tilePlaced(row, col)
    refreshPreview()
    return true
  }

  function chooseJokerLetter(letter) {
    var req = jokerRequest
    jokerRequest = null
    if (!req || !/^[A-Z]$/.test(String(letter))) return
    placeTile(req.tileId, req.row, req.col, String(letter))
  }

  function cancelJoker() {
    jokerRequest = null
  }

  function returnTile(tileId) {
    if (!isPending(tileId)) return
    pending = pending.filter(function(p) { return p.tileId !== tileId })
    refreshPreview()
  }

  function returnTileAt(row, col) {
    var p = pendingAt(row, col)
    if (p) returnTile(p.tileId)
    return !!p
  }

  // Escape: every temporary tile goes back to the rack.
  function recallAll() {
    if (pending.length === 0 && selectedTileId < 0) return false
    pending = []
    selectedTileId = -1
    jokerRequest = null
    refreshPreview()
    return true
  }

  // Rack order is presentation only; the engine never sees it.
  function moveRackTile(fromIndex, toIndex) {
    var key = String(viewer)
    var visible = buildRack().map(function(t) { return t.id })
    if (fromIndex < 0 || fromIndex >= visible.length || toIndex < 0 || toIndex >= visible.length || fromIndex === toIndex) return
    var id = visible.splice(fromIndex, 1)[0]
    visible.splice(toIndex, 0, id)
    var hidden = (rackOrder[key] || []).filter(function(x) { return visible.indexOf(x) === -1 })
    var next = Object.assign({}, rackOrder)
    next[key] = visible.concat(hidden)
    rackOrder = next
    revision++
    persist()
  }

  function swapRackTiles(a, b) {
    var visible = buildRack().map(function(t) { return t.id })
    if (a < 0 || b < 0 || a >= visible.length || b >= visible.length || a === b) return
    var tmp = visible[a]; visible[a] = visible[b]; visible[b] = tmp
    var key = String(viewer)
    var hidden = (rackOrder[key] || []).filter(function(x) { return visible.indexOf(x) === -1 })
    var next = Object.assign({}, rackOrder)
    next[key] = visible.concat(hidden)
    rackOrder = next
    revision++
    persist()
  }

  function shuffleRack() {
    var visible = buildRack().map(function(t) { return t.id })
    for (var i = visible.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1))
      var tmp = visible[i]; visible[i] = visible[j]; visible[j] = tmp
    }
    var key = String(viewer)
    var hidden = (rackOrder[key] || []).filter(function(x) { return visible.indexOf(x) === -1 })
    var next = Object.assign({}, rackOrder)
    next[key] = visible.concat(hidden)
    rackOrder = next
    revision++
    persist()
  }

  // Typing on the board: the next rack tile with `letter` (or a joker) goes
  // to (row, col), skipping squares that already hold a tile. Returns the
  // cell used, or null.
  function typeLetter(letter, row, col, direction) {
    if (!humanTurn || !/^[A-Z]$/.test(letter)) return null
    var r = row, c = col
    while (r <= 14 && c <= 14 && (boardTileAt(r, c) !== null || pendingAt(r, c))) {
      if (direction === "V") r++; else c++
    }
    if (r > 14 || c > 14) return null
    var rack = buildRack()
    var chosen = null
    for (var i = 0; i < rack.length; i++) if (!rack[i].isJoker && rack[i].letter === letter) { chosen = rack[i]; break }
    if (!chosen) for (var j = 0; j < rack.length; j++) if (rack[j].isJoker) { chosen = rack[j]; break }
    if (!chosen) return null
    placeTile(chosen.id, r, c, chosen.isJoker ? letter : null)
    return { row: r, col: c }
  }

  // ------------------------------------------------------------- actions

  function applyGameAction(action) {
    if (!game) return { ok: false }
    var a = Object.assign({}, action)
    if (a.player === game.current) a.elapsedMs = Math.max(0, Date.now() - turnStartedAt)
    var res = guard("action", function() {
      return Engine.applyAction(game, a, { dictionary: provider, now: Date.now() })
    }, { ok: false, message: "Erreur interne." })
    if (!res.ok) {
      moveRejected(res.message || "Coup invalide", res.result || null)
      return res
    }
    var before = game
    game = res.state
    turnStartedAt = Date.now()
    clockNow = turnStartedAt
    syncRackOrder()
    highlightMove = -1
    hintMove = null
    var played = null
    for (var i = 0; i < res.events.length; i++) if (res.events[i].type === "play") played = res.events[i]
    if (played) {
      var move = game.moves[played.moveIndex]
      lastCommitted = { player: played.player, moveIndex: played.moveIndex, score: played.score, bingo: played.bingo, words: move.words }
    }
    revision++
    moveCommitted(res.events, res.result, a.player)
    persist()
    if (game.status === "ended") onGameEnded()
    else afterTurnChange(before)
    return res
  }

  function confirmMove() {
    if (!humanTurn || pending.length === 0) return false
    if (settings.gameplay && settings.gameplay.confirmMoves && !confirmRequested) {
      refreshPreview()
      if (preview && preview.valid) { confirmRequested = true; return false }
    }
    confirmRequested = false
    var placements = pending.slice()
    var res = applyGameAction({ type: "play", player: viewer, placements: placements })
    if (res.ok) {
      pending = []
      selectedTileId = -1
      preview = null
      if (game && game.mode === "practice" && practiceTop) {
        bestMoveReveal = { word: practiceTop.word, score: practiceTop.score, yours: res.result ? res.result.score : 0 }
      }
    }
    return res.ok
  }

  function cancelConfirm() { confirmRequested = false }

  function pass() {
    if (!legal.pass) return false
    recallAll()
    return applyGameAction({ type: "pass", player: viewer }).ok
  }

  function exchange(tileIds) {
    if (!legal.exchange) { say("L’échange n’est possible que s’il reste au moins 7 lettres dans le sac.", "error"); return false }
    recallAll()
    return applyGameAction({ type: "exchange", player: viewer, tileIds: tileIds }).ok
  }

  function challenge() {
    if (!legal.challenge) return false
    recallAll()
    var res = applyGameAction({ type: "challenge", player: viewer })
    if (res.ok) showChallengeOutcome(viewer, res.result)
    return res.ok
  }

  function acceptPending() {
    if (!legal.accept) return false
    return applyGameAction({ type: "accept", player: viewer }).ok
  }

  function resign() {
    if (!isActive) return false
    stopAi()
    recallAll()
    var who = game.mode === "human_vs_human" ? game.current : viewer
    return applyGameAction({ type: "resign", player: who }).ok
  }

  function showChallengeOutcome(challenger, result) {
    var words = result.checked.map(function(c) { return c.word })
    challengeOutcome = {
      challenger: challenger,
      challengerName: playerLabel(challenger),
      success: result.success,
      checked: result.checked,
      invalidWords: result.invalidWords,
      penalty: result.penalty
    }
    lookupForms(words)
    challengeResolved(challengeOutcome)
  }

  function dismissChallenge() { challengeOutcome = null }

  function revealRack() {
    handoverPending = false
    turnStartedAt = Date.now()
  }

  function lookupForms(words) {
    if (!worker || !words || words.length === 0) return
    if (dictionary) dictionary.ensureDisplayForms()
    var missing = words.filter(function(w) { return displayForms[w] === undefined })
    if (missing.length === 0) return
    worker.sendMessage({ type: "lookup", requestId: -2, words: missing })
  }

  function requestHint() {
    if (!humanTurn || !worker || !dictionary || !dictionary.workerReady) return
    hintRequestId = ++requestSerial
    worker.sendMessage({ type: "hint", requestId: hintRequestId, view: Engine.publicView(game, viewer), count: 3 })
  }

  function showHint(index) {
    if (!hints || !hints[index]) { hintMove = null; revision++; return }
    hintMove = hints[index]
    revision++
  }

  // ---------------------------------------------------------- game flow

  function newGame(config) {
    stopAi()
    if (!provider) { say("Le dictionnaire n’est pas encore chargé.", "error"); return false }
    var c = config || {}
    var mode = c.mode || "human_vs_ai"
    var minutes = Number(c.timeMinutes) || 0
    var rules = {
      validation: mode === "practice" ? "immediate" : (c.validation || "immediate"),
      challenge: { penalty: c.challengePenalty || "none", penaltyPoints: 10 },
      time: { totalMs: minutes * 60000, onTimeout: "end_game" }
    }
    var names = c.playerNames || ["Joueur 1", "Joueur 2"]
    var players
    var first = 0
    if (mode === "human_vs_ai") {
      players = [{ name: "Vous", kind: "human" }, { name: "Ordinateur", kind: "ai", difficulty: c.difficulty || "casual" }]
      first = c.firstPlayer === "ai" ? 1 : c.firstPlayer === "random" ? "random" : 0
    } else if (mode === "human_vs_human") {
      players = [{ name: names[0], kind: "human" }, { name: names[1], kind: "human" }]
      first = c.firstPlayer === "random" ? "random" : 0
    } else if (mode === "ai_vs_ai") {
      var d1 = c.difficulty || "expert"
      var d2 = c.difficulty2 || d1
      players = [{ name: "Ordinateur 1", kind: "ai", difficulty: d1 }, { name: "Ordinateur 2", kind: "ai", difficulty: d2 }]
      first = 0
      rules.validation = "immediate"
    } else {
      players = [{ name: names[0] || "Vous", kind: "human" }]
    }
    var created = guard("nouvelle partie", function() {
      return Engine.createGame({
        mode: mode,
        players: players,
        rules: rules,
        dictionary: provider.describe(),
        firstPlayer: first,
        settings: { personality: settings.ai ? settings.ai.personality : "balanced", thinkingScale: settings.ai ? settings.ai.thinkingScale : 1 }
      })
    }, null)
    if (!created) return false
    resetUiState()
    game = created
    syncRackOrder()
    revision++
    persist()
    gameStarted()
    afterTurnChange(null)
    return true
  }

  function resume(state, extras) {
    stopAi()
    resetUiState()
    game = state
    rackOrder = extras && extras.rackOrder && typeof extras.rackOrder === "object" ? extras.rackOrder : ({})
    syncRackOrder()
    revision++
    gameStarted()
    if (game.status === "ended") { endSummary = null; return }
    afterTurnChange(null)
  }

  function resetUiState() {
    pending = []
    selectedTileId = -1
    preview = null
    hoverPreview = null
    jokerRequest = null
    highlightMove = -1
    hintMove = null
    hints = []
    bestMoveReveal = null
    practiceTop = null
    lastCommitted = null
    challengeOutcome = null
    handoverPending = false
    endSummary = null
    confirmRequested = false
    turnStartedAt = Date.now()
    clockNow = turnStartedAt
  }

  function afterTurnChange(before) {
    if (!isActive) return
    var p = game.players[game.current]
    if (game.mode === "human_vs_human" && before && settings.gameplay && settings.gameplay.hideRackBetweenTurns && p.kind === "human")
      handoverPending = true
    if (p.kind === "ai") scheduleAi()
    else if (game.mode === "practice") requestPracticeTop()
  }

  function onGameEnded() {
    stopAi()
    pending = []
    selectedTileId = -1
    if (saves && game.mode !== "ai_vs_ai") endSummary = saves.recordFinishedGame(game, viewerIndex(game))
    gameEnded(game.end)
  }

  function persist() {
    if (saves && game) saves.saveGame(game, { rackOrder: rackOrder })
  }

  // Folds the running turn time into the state (window hidden, shutdown).
  function flushClock() {
    if (!isActive || !clockEnabled) return
    var p = game.current
    if (game.players[p].kind !== "human") return
    var elapsed = Date.now() - turnStartedAt
    if (elapsed <= 0) return
    game = Engine.withElapsed(game, p, elapsed)
    turnStartedAt = Date.now()
    persist()
  }

  onWindowActiveChanged: {
    if (!settings.gameplay || !settings.gameplay.pauseClockWhenHidden) return
    if (!windowActive) flushClock()
    else turnStartedAt = Date.now()
  }

  // ------------------------------------------------------------------ AI

  function stopAi() {
    requestSerial++
    aiRequestId = -1
    aiThinking = false
    queuedAiAction = null
    aiDelay.stop()
  }

  function aiIndex() { return game ? game.current : -1 }

  function scheduleAi() {
    if (!isActive || game.players[game.current].kind !== "ai") return
    if (!worker || !dictionary || !dictionary.workerReady || dictionary.workerDictionaryId !== dictionary.dictionaryId) {
      waitingForWorker = true
      aiThinking = true
      return
    }
    waitingForWorker = false
    aiThinking = true
    aiStarted = Date.now()
    var p = game.current
    var id = ++requestSerial
    aiRequestId = id
    var view = Engine.publicView(game, p)
    var difficulty = game.players[p].difficulty || "casual"
    var s = game.settings || {}
    if (view.pending) {
      worker.sendMessage({ type: "challenge", requestId: id, words: view.pending.words, difficulty: difficulty, seed: Math.floor(Math.random() * 1e9) })
      return
    }
    worker.sendMessage({
      type: "think", requestId: id, view: view, difficulty: difficulty,
      personality: s.personality || (settings.ai ? settings.ai.personality : "balanced"),
      thinkingScale: s.thinkingScale || (settings.ai ? settings.ai.thinkingScale : 1),
      seed: Math.floor(Math.random() * 1e9)
    })
  }

  property double aiStarted: 0

  function requestPracticeTop() {
    practiceTop = null
    if (!worker || !dictionary || !dictionary.workerReady) return
    hintRequestId = ++requestSerial
    practiceRequestId = hintRequestId
    worker.sendMessage({ type: "hint", requestId: hintRequestId, view: Engine.publicView(game, viewer), count: 3 })
  }
  property int practiceRequestId: -1

  function onWorkerMessage(msg) {
    if (!msg) return
    if (msg.type === "ready") {
      if (waitingForWorker) scheduleAi()
      if (game && game.mode === "practice" && isActive) requestPracticeTop()
      return
    }
    if (msg.type === "lookup") {
      var forms = Object.assign({}, displayForms)
      for (var w in msg.results) forms[w] = msg.results[w]
      displayForms = forms
      return
    }
    if (msg.type === "hints") {
      if (msg.requestId === practiceRequestId) {
        practiceTop = msg.moves && msg.moves.length ? msg.moves[0] : null
        hints = msg.moves || []
        return
      }
      if (msg.requestId === hintRequestId) {
        hints = msg.moves || []
        showHint(0)
      }
      return
    }
    if (msg.requestId !== aiRequestId) return // stale: the game moved on
    if (msg.type === "challengeDecision") {
      var p = game.current
      if (msg.challenge) {
        var res = applyGameAction({ type: "challenge", player: p })
        if (res.ok) showChallengeOutcome(p, res.result)
        if (isActive && game.players[game.current].kind === "ai") scheduleAi()
        else aiThinking = false
      } else if (game.pending && game.pending.endsGame) {
        aiThinking = false
        applyGameAction({ type: "accept", player: p })
      } else {
        // Accept silently by playing on: ask for a move without the pending flag.
        var id = ++requestSerial
        aiRequestId = id
        var view = Engine.publicView(game, p)
        view.pending = null
        var s = game.settings || {}
        worker.sendMessage({
          type: "think", requestId: id, view: view, difficulty: game.players[p].difficulty || "casual",
          personality: s.personality || "balanced", thinkingScale: s.thinkingScale || 1, seed: Math.floor(Math.random() * 1e9)
        })
      }
      return
    }
    if (msg.type === "action") {
      aiInfo = msg.info
      queuedAiAction = msg.action
      var wait = Math.max(0, (msg.minMs || 0) - (Date.now() - aiStarted))
      aiDelay.interval = Math.max(1, wait)
      aiDelay.restart()
      return
    }
    if (msg.type === "error") {
      console.warn("omarchy-scrabble: AI error:", msg.stage, msg.message)
      aiThinking = false
      say("L’ordinateur n’a pas pu jouer et passe son tour.", "error")
      if (isActive && game.players[game.current].kind === "ai") applyGameAction({ type: "pass", player: game.current })
    }
  }

  property Timer aiDelay: Timer {
    repeat: false
    onTriggered: {
      var action = ctl.queuedAiAction
      ctl.queuedAiAction = null
      ctl.aiThinking = false
      if (!action || !ctl.isActive) return
      var res = ctl.applyGameAction(action)
      if (!res.ok && ctl.isActive && ctl.game.players[ctl.game.current].kind === "ai") {
        console.warn("omarchy-scrabble: engine refused the AI move:", res.message)
        ctl.applyGameAction({ type: "pass", player: ctl.game.current })
      }
    }
  }

  // ---------------------------------------------------------------- clock

  property Timer clockTimer: Timer {
    interval: 250
    repeat: true
    running: ctl.isActive && ctl.clockEnabled
    onTriggered: {
      ctl.clockNow = Date.now()
      var p = ctl.game.current
      var paused = ctl.settings.gameplay && ctl.settings.gameplay.pauseClockWhenHidden && !ctl.windowActive && ctl.game.players[p].kind === "human"
      if (paused || ctl.handoverPending) return
      if (ctl.game.rules.time.onTimeout === "end_game" && ctl.remainingMs(p) <= 0) {
        ctl.stopAi()
        ctl.applyGameAction({ type: "timeout", player: p })
      }
    }
  }

  property Timer noticeTimer: Timer {
    interval: 4200
    onTriggered: ctl.notice = ""
  }

  // ---------------------------------------------------------- reporting

  // A compact JSON summary, for `omarchy-shell shell call … status`.
  function statusJson() {
    if (!game) return JSON.stringify({ game: null, dictionary: dictionary ? dictionary.status : "none" })
    return JSON.stringify({
      gameId: game.gameId, mode: game.mode, status: game.status, turn: game.turn, current: game.current,
      players: game.players.map(function(p) { return { name: p.name, kind: p.kind, score: p.score, rack: p.rack.length } }),
      bag: game.bag.length, moves: game.moves.length, pending: pending.length, aiThinking: aiThinking,
      dictionary: dictionary ? { id: dictionary.dictionaryId, status: dictionary.status, worker: dictionary.workerReady } : null,
      end: game.end ? { reason: game.end.reason, finalScores: game.end.finalScores, winner: game.end.winner } : null
    })
  }
}
