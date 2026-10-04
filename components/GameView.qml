import QtQuick
import "dialogs"
import "screens"
import "../app/settings.mjs" as SettingsModel
import "../engine/board.mjs" as BoardModel

// The whole game UI. Pure QtQuick on top of the shell's theme tokens; all
// state comes from the GameController, all persistence from the SaveManager.
FocusScope {
  id: view

  property var controller
  property var saves
  property var dictionary
  property var sounds: null
  property bool systemPrefersDark: true
  property bool systemReducedMotion: false
  property bool windowVisible: true

  signal closeRequested()

  readonly property var settings: saves ? saves.settings : SettingsModel.normalizeSettings({})
  readonly property var shortcuts: settings.shortcuts

  // home | setup | game
  property string screen: "home"
  // "" | settings | stats
  property string overlay: ""
  property bool historyOpen: false
  property bool endDismissed: false
  property bool replaying: false

  Theme {
    id: appTheme
    appearance: view.settings.appearance
    systemPrefersDark: view.systemPrefersDark
    animation: view.settings.animation
    systemReducedMotion: view.systemReducedMotion
    highContrast: view.settings.accessibility.highContrast
    largerText: view.settings.accessibility.largerText
    largerTiles: view.settings.accessibility.largerTiles
    premiumLabels: view.settings.accessibility.premiumLabels
  }

  Rectangle {
    anchors.fill: parent
    color: appTheme.background
  }

  // Any pointer press leaves keyboard mode (without stealing the event).
  MouseArea {
    anchors.fill: parent
    z: 1000
    acceptedButtons: Qt.AllButtons
    propagateComposedEvents: true
    onPressed: function(mouse) { view.keyboardMode = false; mouse.accepted = false }
  }

  function showGame() {
    screen = "game"
    overlay = ""
    endDismissed = false
    replaying = false
    keyZone = "rack"
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function startNewGame(config) {
    if (view.controller.newGame(config)) showGame()
  }

  function goHome() {
    overlay = ""
    screen = "home"
    if (controller) controller.recallAll()
  }

  // ------------------------------------------------------------ screens

  HomeScreen {
    id: home
    anchors.fill: parent
    visible: view.screen === "home"
    theme: appTheme
    controller: view.controller
    saves: view.saves
    dictionary: view.dictionary
    onResumeRequested: {
      if (view.controller.hasGame && view.controller.game.gameId === (view.saves.savedGame ? view.saves.savedGame.gameId : "")) view.showGame()
      else if (view.saves.savedGame) { view.controller.resume(view.saves.savedGame, view.saves.savedExtras); view.showGame() }
    }
    onNewGameRequested: view.screen = "setup"
    onStatsRequested: view.overlay = "stats"
    onSettingsRequested: view.overlay = "settings"
  }

  SetupScreen {
    id: setup
    anchors.fill: parent
    visible: view.screen === "setup"
    theme: appTheme
    settings: view.settings
    dictionary: view.dictionary
    onCancelled: view.screen = view.controller.isActive ? "game" : "home"
    onStartRequested: function(config) {
      view.saves.saveSettings(SettingsModel.normalizeSettings(Object.assign({}, view.settings, { newGame: config, ai: Object.assign({}, view.settings.ai, { difficulty: config.difficulty || view.settings.ai.difficulty }) })))
      if (view.dictionary.dictionaryId !== config.dictionary || view.dictionary.status !== "ready") {
        pendingConfig = config
        view.dictionary.load(config.dictionary)
      } else {
        view.startNewGame(config)
      }
    }
    property var pendingConfig: null
    Connections {
      target: view.dictionary
      function onReady() {
        if (setup.pendingConfig) {
          var c = setup.pendingConfig
          setup.pendingConfig = null
          view.startNewGame(c)
        }
      }
    }
  }

  // --------------------------------------------------------- game screen

  Item {
    id: gameScreen
    anchors.fill: parent
    anchors.margins: appTheme.padding
    visible: view.screen === "game"

    readonly property var ctl: view.controller
    readonly property bool wide: width >= height * 1.12 && width >= 820
    readonly property bool practice: ctl && ctl.game ? ctl.game.mode === "practice" : false
    readonly property int playerCount: ctl && ctl.game ? ctl.game.players.length : 0
    readonly property int gap: appTheme.spaceLarge + 2

    readonly property real sidebarWidth: wide ? Math.max(270, Math.min(380, width * 0.3)) : 0
    readonly property real headerHeight: header.implicitHeight
    readonly property real cardsHeight: wide ? 0 : (playerCount > 0 ? cardsRow.implicitHeight : 0)
    readonly property real controlsHeight: appTheme.controlHeight
    // First guess of the board's cell size, to size the rack proportionally.
    readonly property real boardGuess: Math.min(wide ? width - sidebarWidth - gap : width,
      height - headerHeight - cardsHeight - controlsHeight - 4 * gap - 80)
    readonly property real rackTile: Math.round(Math.max(appTheme.largerTiles ? 40 : 34, Math.min(appTheme.largerTiles ? 72 : 62, boardGuess / 15.6 * 1.32)))
    readonly property real rackHeight: rackTile * 1.55
    readonly property real boardSpace: Math.max(200, Math.min(wide ? width - sidebarWidth - gap : width,
      height - headerHeight - cardsHeight - rackHeight - controlsHeight - (wide ? 3 : 4) * gap - (wide ? 0 : previewLine.height)))

    GameHeader {
      id: header
      anchors.left: parent.left
      anchors.right: parent.right
      theme: appTheme
      subtitle: view.gameSubtitle()
      historyAvailable: !gameScreen.wide
      historyOpen: view.historyOpen
      onBackRequested: view.goHome()
      onHistoryRequested: view.historyOpen = !view.historyOpen
      onStatsRequested: view.overlay = "stats"
      onSettingsRequested: view.overlay = "settings"
      onMenuRequested: function(x, y) { menu.openAt(x, y) }
    }

    // Narrow: score cards above the board.
    Row {
      id: cardsRow
      visible: !gameScreen.wide && gameScreen.playerCount > 0
      anchors.top: header.bottom
      anchors.topMargin: gameScreen.gap
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: gameScreen.gap
      Repeater {
        model: gameScreen.wide ? 0 : gameScreen.playerCount
        PlayerCard {
          required property int index
          width: (cardsRow.width - (gameScreen.playerCount - 1) * cardsRow.spacing) / gameScreen.playerCount
          theme: appTheme
          compact: true
          alignRight: index === 1
          name: view.controller.playerLabel(index)
          subtitle: view.controller.difficultyLabel(index)
          score: view.controller.game ? view.controller.game.players[index].score : 0
          active: view.controller.isActive && view.controller.current === index
          thinking: active && view.controller.aiThinking
          status: view.playerStatus(index)
          showClock: view.controller.clockEnabled
          remainingMs: { view.controller.clockNow; return view.controller.remainingMs(index) }
          Connections {
            target: view
            function onScoreFlyout(player, points, bingo) { if (player === index) scored(points, bingo) }
          }
        }
      }
    }

    Item {
      id: boardColumn
      anchors.top: gameScreen.wide ? header.bottom : cardsRow.bottom
      anchors.topMargin: gameScreen.gap
      anchors.left: parent.left
      width: gameScreen.wide ? parent.width - gameScreen.sidebarWidth - gameScreen.gap : parent.width
      anchors.bottom: parent.bottom

      Board {
        id: board
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: gameScreen.boardSpace
        height: gameScreen.boardSpace
        theme: appTheme
        controller: view.controller
        showCoordinates: view.settings.gameplay.showCoordinates
        showLabels: appTheme.premiumLabels
        cursorVisible: view.keyboardMode && view.keyZone === "board" && keys.activeFocus
        cursorRow: view.boardCursor.row
        cursorCol: view.boardCursor.col
        direction: view.typingDirection
        onCellClicked: function(row, col) { view.onBoardClick(row, col) }
        onCellHovered: function(row, col) { view.controller.setHover(row, col) }
        onTilePressed: function(row, col, sx, sy) {
          var info = view.controller.cells[row * 15 + col]
          view.beginDrag(info.tileId, "board", sx, sy)
        }
        onDragMoved: function(sx, sy) { view.moveDrag(sx, sy) }
        onDragReleased: function(sx, sy) { view.endDrag(sx, sy) }
      }

      // Narrow: one line of preview between board and rack.
      Item {
        id: previewLine
        visible: !gameScreen.wide
        anchors.top: board.bottom
        anchors.topMargin: gameScreen.gap / 2
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? previewText.implicitHeight + 4 : 0
        Text {
          id: previewText
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: view.previewSummary()
          color: view.controller.preview && !view.controller.preview.valid ? appTheme.urgent : appTheme.muted
          font.family: appTheme.fontFamily
          font.pixelSize: appTheme.fontSmall
        }
      }

      Rack {
        id: rack
        anchors.horizontalCenter: board.horizontalCenter
        anchors.top: gameScreen.wide ? board.bottom : previewLine.bottom
        anchors.topMargin: gameScreen.gap
        theme: appTheme
        controller: view.controller
        tileSize: gameScreen.rackTile
        tiles: view.controller.rackTiles
        hidden: view.controller.handoverPending
        cursorVisible: view.keyboardMode && view.keyZone === "rack" && keys.activeFocus
        cursorIndex: view.rackCursor
        draggingId: view.dragTileId
        onTileClicked: function(tileId, index) {
          view.rackCursor = index
          view.controller.selectTile(tileId)
          if (view.sounds) view.sounds.play("pickup")
        }
        onDragStarted: function(tileId, sx, sy) { view.beginDrag(tileId, "rack", sx, sy) }
        onDragMoved: function(sx, sy) { view.moveDrag(sx, sy) }
        onDragReleased: function(sx, sy) { view.endDrag(sx, sy) }
      }

      GameControls {
        id: controls
        anchors.top: rack.bottom
        anchors.topMargin: gameScreen.gap
        anchors.horizontalCenter: board.horizontalCenter
        width: Math.max(board.width, rack.width)
        theme: appTheme
        controller: view.controller
        shortcuts: view.shortcuts
        compact: width < 560
        focusIndex: view.keyboardMode && view.keyZone === "controls" && keys.activeFocus ? view.controlIndex : -1
        scoreText: view.scoreSummary()
        scoreValid: !!(view.controller.preview && view.controller.preview.valid)
        onRecallRequested: view.controller.recallAll()
        onShuffleRequested: view.controller.shuffleRack()
        onHintRequested: view.controller.requestHint()
        onExchangeRequested: view.openExchange()
        onPassRequested: view.askPass()
        onPlayRequested: view.playMove()
        onChallengeRequested: view.controller.challenge()
      }
    }

    // Wide: sidebar with cards, the move panel and the history.
    Column {
      id: sidebar
      visible: gameScreen.wide
      anchors.top: header.bottom
      anchors.topMargin: gameScreen.gap
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      width: gameScreen.sidebarWidth
      spacing: gameScreen.gap

      Repeater {
        model: gameScreen.wide ? gameScreen.playerCount : 0
        PlayerCard {
          required property int index
          width: sidebar.width
          theme: appTheme
          name: view.controller.playerLabel(index)
          subtitle: view.controller.difficultyLabel(index)
          score: view.controller.game ? view.controller.game.players[index].score : 0
          active: view.controller.isActive && view.controller.current === index
          thinking: active && view.controller.aiThinking
          status: view.playerStatus(index)
          showClock: view.controller.clockEnabled
          remainingMs: { view.controller.clockNow; return view.controller.remainingMs(index) }
          Connections {
            target: view
            function onScoreFlyout(player, points, bingo) { if (player === index) scored(points, bingo) }
          }
        }
      }

      Rectangle {
        id: movePanel
        width: sidebar.width
        height: movePanelContent.implicitHeight + 2 * appTheme.padding
        radius: appTheme.radius
        color: appTheme.panel
        border.width: appTheme.borderWidth
        border.color: appTheme.line
        Column {
          id: movePanelContent
          x: appTheme.padding
          y: appTheme.padding
          width: parent.width - 2 * appTheme.padding
          spacing: appTheme.space
          Text {
            text: view.controller.pending.length > 0 ? "VOTRE COUP" : view.lastMoveTitle()
            color: appTheme.muted
            font.family: appTheme.fontFamily
            font.pixelSize: appTheme.fontCaption
            font.weight: Font.Bold
            font.letterSpacing: 1.2
          }
          MovePreview {
            width: parent.width
            theme: appTheme
            visible: view.controller.pending.length > 0 && view.settings.gameplay.showScorePreview
            result: view.controller.pending.length > 0 ? view.controller.preview : null
            showValidity: view.settings.gameplay.showWordValidation
          }
          MovePreview {
            width: parent.width
            theme: appTheme
            visible: view.controller.pending.length === 0
            result: view.lastMovePreview()
            emptyText: view.controller.isActive ? (view.controller.humanTurn ? "À vous de jouer. Placez des lettres sur le plateau." : "") : ""
            showValidity: false
          }
          Text {
            visible: !!view.controller.bestMoveReveal
            width: parent.width
            wrapMode: Text.WordWrap
            text: view.controller.bestMoveReveal ? ("Meilleur coup possible : " + view.controller.bestMoveReveal.word + " (" + view.controller.bestMoveReveal.score + " pts)") : ""
            color: appTheme.accent
            font.family: appTheme.fontFamily
            font.pixelSize: appTheme.fontSmall
          }
          Row {
            spacing: appTheme.space
            visible: view.controller.hints.length > 1 && !!view.controller.hintMove
            Repeater {
              model: Math.min(3, view.controller.hints.length)
              GameButton {
                required property int index
                theme: appTheme; compact: true; variant: "ghost"; focusable: false
                text: view.controller.hints[index].word + " " + view.controller.hints[index].score
                checked: view.controller.hintMove === view.controller.hints[index]
                onClicked: view.controller.showHint(index)
              }
            }
          }
        }
      }

      Rectangle {
        width: sidebar.width
        height: Math.max(80, sidebar.height - y)
        radius: appTheme.radius
        color: appTheme.panel
        border.width: appTheme.borderWidth
        border.color: appTheme.line
        Text {
          id: historyTitle
          x: appTheme.padding
          y: appTheme.padding * 0.8
          text: "HISTORIQUE  ·  " + view.controller.bagCount + " lettres dans le sac"
          color: appTheme.muted
          font.family: appTheme.fontFamily
          font.pixelSize: appTheme.fontCaption
          font.weight: Font.Bold
          font.letterSpacing: 1.2
        }
        MoveHistory {
          anchors.top: historyTitle.bottom
          anchors.topMargin: appTheme.space
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: appTheme.spaceSmall
          theme: appTheme
          controller: view.controller
          onMoveActivated: function(index) { view.toggleHighlight(index) }
        }
      }
    }
  }

  // Narrow: history drawer.
  Item {
    id: drawer
    anchors.fill: parent
    visible: view.screen === "game" && !gameScreen.wide && (view.historyOpen || drawerPanel.x < width)
    z: 40
    Rectangle {
      anchors.fill: parent
      color: appTheme.scrim
      opacity: view.historyOpen ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: appTheme.anim(140) } }
      MouseArea { anchors.fill: parent; enabled: view.historyOpen; onClicked: view.historyOpen = false }
    }
    Rectangle {
      id: drawerPanel
      width: Math.min(360, parent.width * 0.85)
      height: parent.height
      x: view.historyOpen ? parent.width - width : parent.width
      Behavior on x { NumberAnimation { duration: appTheme.anim(180); easing.type: Easing.OutCubic } }
      color: appTheme.background
      border.width: appTheme.borderWidth
      border.color: appTheme.line
      Text {
        id: drawerTitle
        x: appTheme.padding; y: appTheme.padding
        text: "HISTORIQUE  ·  " + view.controller.bagCount + " lettres dans le sac"
        color: appTheme.muted
        font.family: appTheme.fontFamily
        font.pixelSize: appTheme.fontCaption
        font.weight: Font.Bold
        font.letterSpacing: 1.2
      }
      MoveHistory {
        anchors.top: drawerTitle.bottom
        anchors.topMargin: appTheme.space
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: appTheme.spaceSmall
        theme: appTheme
        controller: view.controller
        onMoveActivated: function(index) { view.toggleHighlight(index) }
      }
    }
  }

  // ------------------------------------------------------- presentation

  signal scoreFlyout(int player, int points, bool bingo)

  function gameSubtitle() {
    var g = controller ? controller.game : null
    if (!g) return ""
    var mode = g.mode === "human_vs_ai" ? "Contre l’ordinateur" : g.mode === "human_vs_human" ? "Deux joueurs" : "Entraînement"
    var parts = [mode]
    if (g.rules.validation === "challenge") parts.push("avec contestation")
    if (g.rules.time.totalMs > 0) parts.push(Math.round(g.rules.time.totalMs / 60000) + " min")
    parts.push(g.dictionary.name || "Dictionnaire")
    return parts.join("  ·  ")
  }

  function playerStatus(index) {
    var c = controller
    if (!c || !c.game) return ""
    if (c.isOver) {
      var w = c.game.end.winner
      return w === null ? (c.game.players.length > 1 ? "Égalité" : "Partie terminée") : (w === index ? "Victoire" : "")
    }
    if (c.current !== index) return c.game.players[index].rack.length + " lettres"
    if (c.game.players[index].kind === "ai") return c.aiThinking ? "L’ordinateur réfléchit…" : "Tour de l’ordinateur"
    if (c.handoverPending) return "En attente…"
    if (c.game.mode === "human_vs_human") return "À vous, " + c.game.players[index].name
    return "Votre tour"
  }

  function scoreSummary() {
    var c = controller
    if (!c || !c.game) return ""
    if (c.isOver) return "Partie terminée"
    if (!c.humanTurn) return c.aiThinking ? "L’ordinateur réfléchit…" : ""
    var p = c.preview
    if (!p) return c.pending.length ? "" : ""
    if (!view.settings.gameplay.showScorePreview) return p.valid ? "Prêt" : ""
    if (!p.valid && (!p.words || p.words.length === 0)) return ""
    return p.score + " pts" + (p.bingo ? "  ·  Scrabble !" : "")
  }

  function previewSummary() {
    var c = controller
    if (!c || !c.game) return ""
    var p = c.preview
    if (c.pending.length && p) {
      if (!p.valid) return p.message
      return p.words.map(function(w) { return (w.notation || w.word) + " " + w.score }).join("  ·  ") + (p.bingo ? "  ·  +" + p.bonus : "")
    }
    var last = view.lastMovePreview()
    if (last) return lastMoveTitle().toLowerCase() + " : " + last.words.map(function(w) { return (w.notation || w.word) + " " + w.score }).join("  ·  ") + " = " + last.score
    return c.bagCount + " lettres dans le sac"
  }

  function lastMoveTitle() {
    var c = controller
    if (!c || !c.game || !c.lastCommitted) return "DERNIER COUP"
    return "DERNIER COUP · " + c.playerLabel(c.lastCommitted.player).toUpperCase()
  }

  function lastMovePreview() {
    var c = controller
    if (!c || !c.game || !c.lastCommitted) return null
    var m = c.game.moves[c.lastCommitted.moveIndex]
    if (!m || m.withdrawn) return null
    return { valid: true, words: m.words, score: m.score, bingo: m.bingo, bonus: m.bonus }
  }

  function toggleHighlight(index) {
    controller.highlightMove = controller.highlightMove === index ? -1 : index
    controller.revision++
  }

  // ------------------------------------------------------ move handling

  function playMove() {
    if (!controller.humanTurn) return
    if (controller.confirmMove()) return
  }

  function askPass() {
    if (!controller.legal.pass) return
    confirmDialog.ask("pass", "Passer votre tour ?", "Vous ne marquez aucun point ce tour-ci.", "Passer", false)
  }

  function openExchange() {
    if (!controller.legal.exchange) {
      controller.say("L’échange n’est possible que s’il reste au moins 7 lettres dans le sac.", "error")
      return
    }
    controller.recallAll()
    exchangeDialog.tiles = controller.rackTiles
    exchangeDialog.bagCount = controller.bagCount
    exchangeDialog.open = true
  }

  function onBoardClick(row, col) {
    var c = controller
    if (!c.humanTurn) return
    keyZone = "board"
    boardCursor = { row: row, col: col }
    var info = c.cells[row * 15 + col]
    if (info.kind === "pending") {
      c.returnTile(info.tileId)
      if (sounds) sounds.play("pickup")
      return
    }
    if (c.selectedTileId >= 0 && info.kind === "empty") {
      if (c.placeTile(c.selectedTileId, row, col)) {
        if (sounds) sounds.play("place")
        // keep a tile in hand for quick sequences
        var rackNow = c.rackTiles
        if (rackNow.length && rackCursor >= rackNow.length) rackCursor = rackNow.length - 1
      }
    }
  }

  Connections {
    target: view.controller
    function onMoveCommitted(events, result, player) {
      for (var i = 0; i < events.length; i++) {
        var e = events[i]
        if (e.type === "play") {
          view.scoreFlyout(e.player, e.score, e.bingo)
          var cells = []
          for (var k = 0; k < e.cells.length; k++) cells.push(e.cells[k].row * 15 + e.cells[k].col)
          board.flash(cells)
          if (view.sounds) view.sounds.play(e.bingo ? "bingo" : "valid")
        } else if (e.type === "challenge" && e.penalty && e.penalty.type === "points") {
          view.scoreFlyout(e.player, -e.penalty.points, false)
        } else if (e.type === "move_withdrawn") {
          if (view.sounds) view.sounds.play("invalid")
        } else if (e.type === "game_over") {
          view.endDismissed = false
        }
      }
    }
    function onMoveRejected(message, result) {
      view.controller.say(message, "error")
      if (view.sounds) view.sounds.play("invalid")
    }
    function onGameEnded(end) {
      view.endDismissed = false
      if (view.sounds) view.sounds.play(end.winner === 0 || end.winner === null ? "victory" : "valid")
    }
  }

  // ------------------------------------------------------------ dragging

  property int dragTileId: -1
  property string dragSource: ""
  property real dragX: 0
  property real dragY: 0

  function beginDrag(tileId, source, sx, sy) {
    if (!controller.humanTurn || tileId < 0) return
    dragTileId = tileId
    dragSource = source
    controller.selectedTileId = tileId
    var p = view.mapFromItem(null, sx, sy)
    dragX = p.x; dragY = p.y
    if (sounds) sounds.play("pickup")
  }

  function moveDrag(sx, sy) {
    if (dragTileId < 0) return
    var p = view.mapFromItem(null, sx, sy)
    dragX = p.x; dragY = p.y
    var cell = board.cellAtScene(sx, sy)
    board.dropRow = cell ? cell.row : -1
    board.dropCol = cell ? cell.col : -1
    if (cell) controller.setHover(cell.row, cell.col)
    else controller.setHover(-1, -1)
  }

  function endDrag(sx, sy) {
    if (dragTileId < 0) return
    var id = dragTileId
    var source = dragSource
    dragTileId = -1
    dragSource = ""
    board.dropRow = -1
    board.dropCol = -1
    controller.setHover(-1, -1)
    var cell = board.cellAtScene(sx, sy)
    if (cell && controller.cells[cell.row * 15 + cell.col].kind === "empty") {
      if (controller.placeTile(id, cell.row, cell.col) && sounds) sounds.play("place")
      return
    }
    if (rack.containsScene(sx, sy)) {
      if (source === "board") controller.returnTile(id)
      else {
        var from = -1
        var list = controller.rackTiles
        for (var i = 0; i < list.length; i++) if (list[i].id === id) from = i
        var to = rack.indexAtScene(sx, sy)
        if (from >= 0 && to >= 0) controller.moveRackTile(from, to)
      }
      controller.selectedTileId = -1
      return
    }
    if (source === "board") controller.returnTile(id)
    controller.selectedTileId = -1
  }

  Tile {
    id: dragProxy
    z: 90
    visible: view.dragTileId >= 0
    theme: appTheme
    size: Math.round(Math.max(board.cellSize, gameScreen.rackTile * 0.9))
    x: view.dragX - size / 2
    y: view.dragY - size / 2
    selected: true
    readonly property var t: view.dragTileId >= 0 && view.controller.game ? view.controller.game.tiles[view.dragTileId] : null
    letter: t ? (t.isJoker ? "?" : t.letter) : ""
    points: t ? t.points : 0
    joker: t ? t.isJoker : false
  }

  // ------------------------------------------------------------ keyboard

  property string keyZone: "rack"        // rack | board | controls
  // Cursors and focus rings show once the keyboard is used, and hide again
  // on pointer use — the "focus-visible" convention.
  property bool keyboardMode: false
  property int rackCursor: 0
  property int controlIndex: 0
  property var boardCursor: ({ row: 7, col: 7 })
  property string typingDirection: "H"
  property var typedCells: []
  property var typingStart: null

  function shortcut(name, event) {
    return SettingsModel.matchesShortcut(view.shortcuts[name], event, Qt)
  }

  function moveBoardCursor(dr, dc) {
    var r = Math.max(0, Math.min(14, boardCursor.row + dr))
    var c = Math.max(0, Math.min(14, boardCursor.col + dc))
    boardCursor = { row: r, col: c }
    controller.setHover(r, c)
  }

  function handleGameKey(event) {
    var c = controller
    if (!c || !c.game) return false
    var noMods = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) === 0
    var letter = String(event.text || "").toUpperCase()
    var typing = keyZone === "board" && noMods && /^[A-Z]$/.test(letter) && view.settings.gameplay.assistedPlacement

    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      var zones = ["rack", "board", "controls"]
      var i = zones.indexOf(keyZone)
      var back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
      if (keyZone === "controls" && !back && controlIndex < controls.buttons.length - 1) { controlIndex++; return true }
      if (keyZone === "controls" && back && controlIndex > 0) { controlIndex--; return true }
      keyZone = zones[(i + (back ? 2 : 1)) % 3]
      if (keyZone === "controls") controlIndex = back ? controls.buttons.length - 1 : 0
      if (keyZone === "board") c.setHover(boardCursor.row, boardCursor.col)
      else c.setHover(-1, -1)
      return true
    }

    if (shortcut("help", event)) { shortcutsDialog.open = true; return true }
    if (shortcut("save", event)) { c.persist(); c.say("Partie sauvegardée.", "info"); return true }
    if (shortcut("cancel", event)) {
      if (c.recallAll()) {
        typedCells = []
        // Back to where the typing began, ready to try another word.
        if (typingStart) boardCursor = typingStart
        typingStart = null
        return true
      }
      if (view.historyOpen) { view.historyOpen = false; return true }
      if (c.highlightMove >= 0 || c.hintMove) { c.highlightMove = -1; c.hintMove = null; c.revision++; return true }
      return false
    }
    if (shortcut("confirm", event) && keyZone !== "controls") { playMove(); return true }

    if (typing) {
      if (c.pending.length === 0) typingStart = { row: boardCursor.row, col: boardCursor.col }
      var at = c.typeLetter(letter, boardCursor.row, boardCursor.col, typingDirection)
      if (at) {
        typedCells = typedCells.concat([at])
        var nr = typingDirection === "V" ? at.row + 1 : at.row
        var nc = typingDirection === "H" ? at.col + 1 : at.col
        boardCursor = { row: Math.min(14, nr), col: Math.min(14, nc) }
        if (sounds) sounds.play("place")
      }
      return true
    }

    // Letter shortcuts only outside the board (where letters type).
    if (keyZone !== "board" || !noMods) {
      if (shortcut("shuffle", event)) { c.shuffleRack(); return true }
      if (shortcut("pass", event)) { askPass(); return true }
      if (shortcut("exchange", event)) { openExchange(); return true }
      if (shortcut("challenge", event)) { if (c.legal.challenge) c.challenge(); return true }
      if (shortcut("newGame", event)) { askNewGame(); return true }
      if (shortcut("hint", event)) { if (gameScreen.practice) c.requestHint(); return true }
      if (shortcut("history", event)) { if (!gameScreen.wide) view.historyOpen = !view.historyOpen; return true }
    }

    if (keyZone === "rack") {
      var tiles = c.rackTiles
      if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
        var d = event.key === Qt.Key_Left ? -1 : 1
        var target = Math.max(0, Math.min(tiles.length - 1, rackCursor + d))
        if (event.modifiers & Qt.ShiftModifier) c.moveRackTile(rackCursor, target)
        rackCursor = target
        return true
      }
      if (event.key === Qt.Key_Up) { keyZone = "board"; c.setHover(boardCursor.row, boardCursor.col); return true }
      if (shortcut("select", event)) {
        if (tiles[rackCursor]) { c.selectTile(tiles[rackCursor].id); if (sounds) sounds.play("pickup") }
        return true
      }
      return false
    }

    if (keyZone === "board") {
      if (event.key === Qt.Key_Left) { typingDirection = "H"; moveBoardCursor(0, -1); return true }
      if (event.key === Qt.Key_Right) { typingDirection = "H"; moveBoardCursor(0, 1); return true }
      if (event.key === Qt.Key_Up) { typingDirection = "V"; moveBoardCursor(-1, 0); return true }
      if (event.key === Qt.Key_Down) {
        if (boardCursor.row === 14) { keyZone = "rack"; c.setHover(-1, -1); return true }
        typingDirection = "V"; moveBoardCursor(1, 0); return true
      }
      if (event.key === Qt.Key_Backspace) {
        if (typedCells.length) {
          var last = typedCells[typedCells.length - 1]
          typedCells = typedCells.slice(0, -1)
          c.returnTileAt(last.row, last.col)
          boardCursor = { row: last.row, col: last.col }
        } else {
          c.returnTileAt(boardCursor.row, boardCursor.col)
        }
        return true
      }
      if (event.key === Qt.Key_Delete) { c.returnTileAt(boardCursor.row, boardCursor.col); return true }
      if (shortcut("select", event)) {
        var info = c.cells[boardCursor.row * 15 + boardCursor.col]
        if (info.kind === "pending") {
          c.returnTile(info.tileId)
          c.selectTile(info.tileId)
        } else if (c.selectedTileId >= 0 && info.kind === "empty") {
          if (c.placeTile(c.selectedTileId, boardCursor.row, boardCursor.col) && sounds) sounds.play("place")
        } else if (info.kind === "empty") {
          typingDirection = typingDirection === "H" ? "V" : "H"
          c.say(typingDirection === "H" ? "Saisie horizontale" : "Saisie verticale", "info")
        }
        return true
      }
      return false
    }

    if (keyZone === "controls") {
      if (event.key === Qt.Key_Left) { controlIndex = Math.max(0, controlIndex - 1); return true }
      if (event.key === Qt.Key_Right) { controlIndex = Math.min(controls.buttons.length - 1, controlIndex + 1); return true }
      if (event.key === Qt.Key_Up) { keyZone = "rack"; return true }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { controls.activate(controlIndex); return true }
      return false
    }
    return false
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true
    Keys.onPressed: function(event) {
      if (view.screen === "game" && view.overlay === "") {
        if (view.handleGameKey(event)) { event.accepted = true; view.keyboardMode = true }
      } else if (view.screen !== "game" && event.key === Qt.Key_Escape && view.overlay === "") {
        if (view.screen === "setup") { view.screen = view.controller.isActive ? "game" : "home"; event.accepted = true }
      }
    }
  }

  function askNewGame() {
    if (controller.isActive && controller.game.moves.length > 0)
      confirmDialog.ask("newgame", "Commencer une nouvelle partie ?", "La partie en cours sera abandonnée et comptera comme une défaite contre l’ordinateur.", "Nouvelle partie", true)
    else view.screen = "setup"
  }

  // ------------------------------------------------------------- dialogs

  JokerPicker {
    theme: appTheme
    open: view.controller.jokerRequest !== null
    onChosen: function(letter) {
      view.controller.chooseJokerLetter(letter)
      if (view.sounds) view.sounds.play("place")
      keys.forceActiveFocus()
    }
    onCancelled: { view.controller.cancelJoker(); keys.forceActiveFocus() }
  }

  ExchangeDialog {
    id: exchangeDialog
    theme: appTheme
    onConfirmed: function(ids) {
      open = false
      view.controller.exchange(ids)
      keys.forceActiveFocus()
    }
    onCancelled: { open = false; keys.forceActiveFocus() }
  }

  ConfirmDialog {
    id: confirmDialog
    theme: appTheme
    property string action: ""
    function ask(what, t, m, label, destructive) {
      action = what; title = t; message = m; confirmText = label; confirmDialog.destructive = destructive; open = true
    }
    onConfirmed: {
      open = false
      if (action === "pass") view.controller.pass()
      else if (action === "resign") view.controller.resign()
      else if (action === "newgame") { view.controller.resign(); view.screen = "setup" }
      keys.forceActiveFocus()
    }
    onCancelled: { open = false; keys.forceActiveFocus() }
  }

  ConfirmDialog {
    id: moveConfirm
    theme: appTheme
    open: view.controller.confirmRequested
    title: "Jouer ce coup ?"
    message: view.controller.preview ? view.controller.preview.words.map(function(w) { return (w.notation || w.word) + " " + w.score }).join(" · ") + " — total " + view.controller.preview.score + " pts" : ""
    confirmText: "Jouer"
    cancelText: "Modifier"
    onConfirmed: { view.controller.confirmMove(); keys.forceActiveFocus() }
    onCancelled: { view.controller.cancelConfirm(); keys.forceActiveFocus() }
  }

  ChallengeDialog {
    theme: appTheme
    viewer: view.controller ? view.controller.viewer : 0
    open: view.controller.challengeOutcome !== null
    outcome: view.controller.challengeOutcome
    forms: view.controller.displayForms
    dictionaryName: view.controller.game ? view.controller.game.dictionary.name : ""
    onClosed: { view.controller.dismissChallenge(); keys.forceActiveFocus() }
  }

  HandoverDialog {
    theme: appTheme
    open: view.screen === "game" && view.controller.handoverPending
    playerName: view.controller.game ? view.controller.playerLabel(view.controller.current) : ""
    lastMoveText: {
      var p = view.lastMovePreview()
      return p ? view.controller.playerLabel(view.controller.lastCommitted.player) + " a joué " + p.words[0].word + " (" + p.score + " pts)." : ""
    }
    onReveal: { view.controller.revealRack(); keys.forceActiveFocus() }
  }

  ShortcutsDialog {
    id: shortcutsDialog
    theme: appTheme
    shortcuts: view.shortcuts
    onClosed: { open = false; keys.forceActiveFocus() }
  }

  PopupMenu {
    id: menu
    theme: appTheme
    items: [
      { id: "new", text: "Nouvelle partie", enabled: true },
      { id: "resign", text: "Abandonner la partie", enabled: view.controller.isActive },
      { id: "replay", text: "Revoir la partie", enabled: !!(view.controller.game && view.controller.game.moves.length) },
      { id: "shortcuts", text: "Raccourcis clavier", enabled: true },
      { id: "about", text: "Dictionnaire et licences", enabled: true }
    ]
    onActivated: function(id) {
      if (id === "new") view.askNewGame()
      else if (id === "resign") confirmDialog.ask("resign", "Abandonner la partie ?", "La partie s’arrête et compte comme une défaite.", "Abandonner", true)
      else if (id === "replay") view.replaying = true
      else if (id === "shortcuts") shortcutsDialog.open = true
      else if (id === "about") { view.overlay = "settings"; settingsScreen.section = "about" }
    }
  }

  // ------------------------------------------------------------ overlays

  EndScreen {
    anchors.fill: parent
    z: 60
    theme: appTheme
    controller: view.controller
    visible: view.screen === "game" && view.controller.isOver && !view.endDismissed && !view.replaying
    onNewGameRequested: view.screen = "setup"
    onReplayRequested: view.replaying = true
    onRematchRequested: view.startNewGame(view.settings.newGame ? Object.assign({}, view.settings.newGame, { difficulty: view.settings.ai.difficulty }) : {})
    onCloseRequested: view.endDismissed = true
  }

  ReplayBar {
    id: replayBar
    z: 61
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: appTheme.padding
    theme: appTheme
    controller: view.controller
    active: view.replaying && view.screen === "game"
    visible: active
    onClosed: view.replaying = false
  }

  StatsScreen {
    anchors.fill: parent
    z: 70
    visible: view.overlay === "stats"
    theme: appTheme
    saves: view.saves
    onClosed: { view.overlay = ""; keys.forceActiveFocus() }
  }

  SettingsScreen {
    id: settingsScreen
    anchors.fill: parent
    z: 70
    visible: view.overlay === "settings"
    theme: appTheme
    saves: view.saves
    dictionary: view.dictionary
    onClosed: { view.overlay = ""; keys.forceActiveFocus() }
  }

  LoadingScreen {
    anchors.fill: parent
    z: 80
    theme: appTheme
    dictionary: view.dictionary
    saves: view.saves
    visible: !view.saves || !view.saves.ready || !view.dictionary || view.dictionary.status === "loading" || view.dictionary.status === "idle"
  }

  RecoveryScreen {
    anchors.fill: parent
    z: 85
    theme: appTheme
    dictionary: view.dictionary
    saves: view.saves
    visible: !!view.dictionary && (view.dictionary.status === "missing" || view.dictionary.status === "error")
  }

  // Save problems and notices: a quiet line at the bottom.
  Rectangle {
    id: toast
    z: 95
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: appTheme.padding + (replayBar.visible ? replayBar.height + appTheme.space : 0)
    width: Math.min(parent.width - 2 * appTheme.padding, toastText.implicitWidth + 2 * appTheme.padding)
    height: toastText.implicitHeight + appTheme.padding
    radius: appTheme.radius
    color: view.controller && view.controller.noticeKind === "error" ? appTheme.mix(appTheme.background, appTheme.urgent, 0.18) : appTheme.panelStrong
    border.width: appTheme.borderWidth
    border.color: view.controller && view.controller.noticeKind === "error" ? appTheme.alpha(appTheme.urgent, 0.6) : appTheme.line
    opacity: view.controller && view.controller.notice !== "" ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: appTheme.anim(160) } }
    Text {
      id: toastText
      anchors.centerIn: parent
      width: Math.min(implicitWidth, view.width - 4 * appTheme.padding)
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      text: view.controller ? view.controller.notice : ""
      color: appTheme.foreground
      font.family: appTheme.fontFamily
      font.pixelSize: appTheme.fontBody
    }
  }

  // Shown once after a save could not be read: it was kept, not deleted.
  ConfirmDialog {
    theme: appTheme
    open: !!(view.saves && view.saves.problem) && view.screen !== "game"
    title: "Une sauvegarde n’a pas pu être lue"
    message: view.saves && view.saves.problem
      ? (view.saves.problem.message + "\n\nLe fichier n’a pas été supprimé : il est conservé ici :\n" + view.saves.problem.keptAs)
      : ""
    confirmText: "Compris"
    cancelText: "Fermer"
    onConfirmed: view.saves.dismissProblem()
    onCancelled: view.saves.dismissProblem()
  }

  onScreenChanged: Qt.callLater(function() { if (view.screen === "game") keys.forceActiveFocus() })
  Component.onCompleted: keys.forceActiveFocus()
}
