import QtQuick
import "dialogs"
import "screens"
import "../app/settings.mjs" as SettingsModel
import "../engine/board.mjs" as BoardModel
import "../app/i18n/i18n.mjs" as I18n

// The whole game UI. Pure QtQuick on top of the shell's theme tokens; all
// state comes from the GameController, all persistence from the SaveManager.
FocusScope {
  id: view

  property var controller
  property var saves
  property var dictionary
  property var sounds: null
  property var definitions: null
  property var online: null       // OnlineService
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
    language: I18n.resolveLanguage(view.settings.language, Qt.locale().name)
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

  function askResetStats() {
    confirmDialog.ask("resetStats", tr("confirm.resetStats.title"), tr("confirm.resetStats.message"), tr("confirm.resetStats.button"), true)
  }

  function openSettings(section) {
    settingsScreen.section = section || ""
    overlay = "settings"
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
    onJoinRequested: view.openOnline("join")
  }

  OnlineScreen {
    id: onlineScreen
    anchors.fill: parent
    visible: view.screen === "online"
    theme: appTheme
    online: view.online
    settings: view.settings
    saves: view.saves
    dictionary: view.dictionary
    onClosed: view.screen = view.controller.isActive ? "game" : "home"
    onAcceptRequested: function(config) {
      // The game needs the same word list as the inviter's.
      if (config && config.dictionary && view.dictionary.dictionaryId !== config.dictionary) view.dictionary.load(config.dictionary)
      view.online.accept()
    }
  }

  // A friend's invitation, wherever the player is.
  ConfirmDialog {
    id: callDialog
    theme: appTheme
    readonly property var call: view.online ? view.online.incomingCall : null
    readonly property bool missing: !!call && !!view.dictionary && view.dictionary.installed[call.config.dictionary || "open-fr"] !== true
    readonly property bool replaces: !!view.controller && view.controller.isActive
    open: !!call
    title: call ? tr("online.proposal", { name: call.name }) : ""
    message: !call ? "" : onlineScreen.configSummary(call.config)
      + (missing ? "\n\n" + tr("online.error.dictionary", { name: tr("dict." + (call.config.dictionary || "open-fr") + ".label") }) : "")
      + (!missing && replaces ? "\n\n" + tr("online.call.replaces") : "")
    confirmText: tr(missing ? "online.decline" : "online.accept")
    cancelText: tr("online.decline")
    destructive: replaces && !missing
    onConfirmed: {
      var c = call
      if (!c) return
      if (missing) { view.online.answer(false); return }
      if (view.controller.isActive) view.controller.resign()
      var dict = c.config.dictionary || "open-fr"
      if (view.dictionary.dictionaryId !== dict || view.dictionary.status !== "ready") view.dictionary.load(dict)
      view.online.answer(true)
      view.openOnline("join")
    }
    onCancelled: view.online.answer(false)
    onCallChanged: if (call && view.controller && !view.controller.windowActive) view.controller.notify(tr("online.notify.title"), tr("online.call.notify", { name: call.name }))
  }

  function openOnline(mode) {
    onlineScreen.mode = mode
    if (mode === "join" && online && online.stage !== "proposal" && online.stage !== "dealing") online.stage = ""
    screen = "online"
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
      if (config.mode === "online") {
        view.saves.saveSettings(SettingsModel.normalizeSettings(Object.assign({}, view.settings, { newGame: config })))
        if (view.dictionary.dictionaryId !== config.dictionary || view.dictionary.status !== "ready") view.dictionary.load(config.dictionary)
        onlineScreen.gameConfig = { mode: "online", gameLanguage: config.gameLanguage, dictionary: config.dictionary,
                                    timeMinutes: config.timeMinutes, validation: config.validation, challengePenalty: config.challengePenalty }
        view.openOnline("invite")
        view.online.invite({ mode: "online", gameLanguage: config.gameLanguage, dictionary: config.dictionary,
                             timeMinutes: config.timeMinutes, validation: config.validation, challengePenalty: config.challengePenalty })
        return
      }
      view.saves.saveSettings(SettingsModel.normalizeSettings(Object.assign({}, view.settings, { newGame: config, ai: Object.assign({}, view.settings.ai, { difficulty: config.difficulty || view.settings.ai.difficulty }) })))
      if (view.dictionary.dictionaryId !== config.dictionary || view.dictionary.status !== "ready") {
        pendingConfig = config
        view.dictionary.load(config.dictionary)
      } else {
        view.startNewGame(config)
      }
    }
    property var pendingConfig: null
  }

  property var connectedDictionary: null
  onDictionaryChanged: {
    if (connectedDictionary === dictionary || !dictionary) return
    dictionary.ready.connect(function() {
      if (setup.pendingConfig) {
        var c = setup.pendingConfig
        setup.pendingConfig = null
        view.startNewGame(c)
      }
    })
    connectedDictionary = dictionary
  }

  // --------------------------------------------------------- game screen

  Item {
    id: gameScreen
    anchors.fill: parent
    anchors.margins: appTheme.padding
    visible: view.screen === "game"

    readonly property var ctl: view.controller
    readonly property bool wide: width >= height * 1.12 && width >= 820
    // Wide but short (laptop screens): the rack and the buttons move to the
    // side column so the board can use the full height.
    readonly property bool dock: wide && height < 820
    readonly property bool practice: ctl && ctl.game ? ctl.game.mode === "practice" : false
    readonly property int playerCount: ctl && ctl.game ? ctl.game.players.length : 0
    readonly property int gap: appTheme.spaceLarge + 2

    readonly property real sidebarWidth: !wide ? 0 : dock ? Math.max(300, Math.min(400, width * 0.32)) : Math.max(270, Math.min(380, width * 0.3))
    readonly property real headerHeight: header.implicitHeight
    readonly property real cardsHeight: wide ? 0 : (playerCount > 0 ? cardsRow.implicitHeight : 0)
    readonly property real controlsHeight: appTheme.controlHeight
    // First guess of the board's cell size, to size the rack proportionally.
    readonly property real boardGuess: Math.min(wide ? width - sidebarWidth - gap : width,
      height - headerHeight - cardsHeight - controlsHeight - 4 * gap - 80)
    readonly property real rackTile: dock
      ? Math.floor(Math.max(30, Math.min(appTheme.largerTiles ? 60 : 54, sidebarWidth / 8.24)))
      : Math.round(Math.max(appTheme.largerTiles ? 40 : 34, Math.min(appTheme.largerTiles ? 72 : 62, boardGuess / 15.6 * 1.32)))
    readonly property real rackHeight: rackTile * 1.55
    readonly property real boardSpace: dock
      ? Math.max(200, Math.min(width - sidebarWidth - gap, height - headerHeight - gap))
      : Math.max(200, Math.min(wide ? width - sidebarWidth - gap : width,
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
        notation: view.controller ? view.controller.gameLanguage : "fr"
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
          textFormat: Text.PlainText
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

    }


    // Rack and buttons: under the board, or in the side column (dock).
    Item {
      id: playArea
      z: 2
      width: gameScreen.dock ? gameScreen.sidebarWidth : Math.max(board.width, rack.width)
      height: rack.height + gameScreen.gap + controls.height
      x: gameScreen.dock ? sidebar.x : boardColumn.x + (boardColumn.width - width) / 2
      y: gameScreen.dock ? sidebar.y + dockSlot.y
         : boardColumn.y + (previewLine.visible ? previewLine.y + previewLine.height : board.y + board.height) + gameScreen.gap

      Rack {
        id: rack
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        theme: appTheme
        controller: view.controller
        tileSize: gameScreen.rackTile
        tiles: view.controller.rackTiles
        hidden: view.controller.handoverPending || (view.controller.game !== null && view.controller.game.mode === "ai_vs_ai")
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
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        theme: appTheme
        controller: view.controller
        shortcuts: view.shortcuts
        compact: width < 560 || gameScreen.dock
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
      }    }

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

      // Dock: room for the rack and buttons (placed over it by playArea).
      Item {
        id: dockSlot
        visible: gameScreen.dock
        width: sidebar.width
        height: visible ? playArea.height : 0
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
            textFormat: Text.PlainText
            text: view.controller.pending.length > 0 ? tr("panel.yourMove") : view.lastMoveTitle()
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
            clickable: true
            onWordActivated: function(word) {
              if (view.controller.lastCommitted) view.showMoveWords(view.controller.lastCommitted.moveIndex)
            }
            emptyText: view.controller.isActive ? (view.controller.humanTurn ? tr("panel.yourTurnHint") : "") : ""
            showValidity: false
          }
          Text {
            textFormat: Text.PlainText
            visible: !!view.controller.bestMoveReveal
            width: parent.width
            wrapMode: Text.WordWrap
            text: view.controller.bestMoveReveal ? tr("panel.bestMove", { word: view.controller.bestMoveReveal.word, score: view.controller.bestMoveReveal.score }) : ""
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
          textFormat: Text.PlainText
          id: historyTitle
          x: appTheme.padding
          y: appTheme.padding * 0.8
          text: tr("panel.history", { bag: tr("common.tilesInBag", { n: view.controller.bagCount }) })
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
        textFormat: Text.PlainText
        id: drawerTitle
        x: appTheme.padding; y: appTheme.padding
        text: tr("panel.history", { bag: tr("common.tilesInBag", { n: view.controller.bagCount }) })
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
  function tr(key, args) { return appTheme.t(key, args) }

  function gameSubtitle() {
    var g = controller ? controller.game : null
    if (!g) return ""
    var parts = [g.mode === "human_vs_human" ? tr("mode.human_vs_human.short") : tr("mode." + g.mode)]
    if (g.mode === "online" && g.online) parts.push(tr("online.against", { name: controller.playerLabel(1 - g.online.seat) }))
    if (g.rules.validation === "challenge") parts.push(tr("mode.withChallenge"))
    if (g.rules.time.totalMs > 0) parts.push(tr("common.minutes", { n: Math.round(g.rules.time.totalMs / 60000) }))
    parts.push(tr("dict." + (g.dictionary.id || "open-fr") + ".label"))
    return parts.join("  ·  ")
  }

  function playerStatus(index) {
    var c = controller
    if (!c || !c.game) return ""
    if (c.isOver) {
      var w = c.game.end.winner
      return w === null ? tr(c.game.players.length > 1 ? "status.draw" : "status.gameOver") : (w === index ? tr("status.victory") : "")
    }
    if (c.current !== index) return tr("status.tiles", { n: c.game.players[index].rack.length })
    if (c.isOnline && index !== c.viewer)
      return tr(view.online && !view.online.peerConnected ? "online.status.offline" : "online.status.theirTurn", { name: c.playerLabel(index) })
    if (c.game.players[index].kind === "ai") return tr(c.aiThinking ? "status.computerThinking" : "status.computerTurn")
    if (c.handoverPending) return tr("status.waiting")
    if (c.game.mode === "human_vs_human") return tr("status.yourTurnNamed", { name: c.playerLabel(index) })
    return tr("status.yourTurn")
  }

  function scoreSummary() {
    var c = controller
    if (!c || !c.game) return ""
    if (c.isOnline) {
      if (c.onlineWork === "shuffling") return tr("online.status.shuffling")
      if (c.onlineWork === "checking") return tr("online.status.checking")
      if (c.isActive && c.rackRevealing) return tr("online.status.revealing")
      if (c.isActive && c.current !== c.viewer)
        return tr(view.online && !view.online.peerConnected ? "online.status.offline" : "online.status.theirTurn", { name: c.playerLabel(c.current) })
    }
    if (c.isOver) return tr("status.gameOver")
    if (!c.humanTurn) return c.aiThinking ? tr("status.computerThinking") : ""
    var p = c.preview
    if (!p) return c.pending.length ? "" : ""
    if (!view.settings.gameplay.showScorePreview) return p.valid ? tr("status.ready") : ""
    if (!p.valid && (!p.words || p.words.length === 0)) return ""
    return tr("common.pts", { n: p.score }) + (p.bingo ? "  ·  " + tr("status.scrabble") : "")
  }

  function previewSummary() {
    var c = controller
    if (!c || !c.game) return ""
    var p = c.preview
    if (c.pending.length && p) {
      if (!p.valid) return c.reasonText(p.reason, p)
      return p.words.map(function(w) { return (w.notation || w.word) + " " + w.score }).join("  ·  ") + (p.bingo ? "  ·  +" + p.bonus : "")
    }
    var last = view.lastMovePreview()
    if (last) return lastMoveTitle().toLowerCase() + tr("common.colon") + last.words.map(function(w) { return (w.notation || w.word) + " " + w.score }).join("  ·  ") + " = " + last.score
    return tr("common.tilesInBag", { n: c.bagCount })
  }

  function lastMoveTitle() {
    var c = controller
    if (!c || !c.game || !c.lastCommitted) return tr("panel.lastMove")
    return tr("panel.lastMoveBy", { name: c.playerLabel(c.lastCommitted.player).toUpperCase() })
  }

  function lastMovePreview() {
    var c = controller
    if (!c || !c.game || !c.lastCommitted) return null
    var m = c.game.moves[c.lastCommitted.moveIndex]
    if (!m || m.withdrawn) return null
    return { valid: true, words: m.words, score: m.score, bingo: m.bingo, bonus: m.bonus }
  }

  function toggleHighlight(index) {
    controller.highlightMove = index
    controller.revision++
    showMoveWords(index)
  }

  // Definitions of the words a move formed.
  function showMoveWords(index) {
    var m = controller.game ? controller.game.moves[index] : null
    if (!m || m.type !== "play") return
    var words = m.words.map(function(w) { return w.word })
    openWords(words, controller.playerLabel(m.player) + "  ·  " + m.position + "  ·  " + tr("common.pts", { n: m.score }) + (m.withdrawn ? "  ·  " + tr("panel.moveCancelled") : ""))
  }
  function openWords(words, subtitle) {
    if (!words || !words.length) return
    controller.lookupForms(words)
    if (definitions) definitions.refresh()
    wordDialog.words = words
    wordDialog.subtitle = subtitle || ""
    wordDialog.open = true
  }

  // ------------------------------------------------------ move handling

  function playMove() {
    if (!controller.humanTurn) return
    if (controller.confirmMove()) return
  }

  function askPass() {
    if (!controller.legal.pass) return
    confirmDialog.ask("pass", tr("confirm.pass.title"), tr("confirm.pass.message"), tr("confirm.pass.button"), false)
  }

  function openExchange() {
    if (!controller.legal.exchange) {
      controller.say(tr("notice.exchangeNeedsBag"), "error")
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

  // Controller signals, connected once the host injects the controller (a
  // Connections element with a null target would warn during injection).
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
  // A definitions download started here may end while another screen (or
  // none) is showing: say how it went.
  function onDefinitionsInstalled(language, ok) {
    if (!controller || (definitions.job && definitions.job.stage === "cancelled")) return
    controller.say(tr(ok ? "defs.done" : "defs.failed"), ok ? "info" : "error")
  }
  property var connectedDefinitions: null
  onDefinitionsChanged: {
    if (connectedDefinitions === definitions || !definitions) return
    definitions.installFinished.connect(view.onDefinitionsInstalled)
    connectedDefinitions = definitions
  }

  property var connectedController: null
  onControllerChanged: {
    if (connectedController === controller || !controller) return
    controller.tr = function(key, args) { return appTheme.t(key, args) }
    controller.moveCommitted.connect(view.onMoveCommitted)
    controller.gameStarted.connect(function() { if (view.screen === "online") view.showGame() })
    controller.moveRejected.connect(view.onMoveRejected)
    controller.gameEnded.connect(view.onGameEnded)
    connectedController = controller
  }

  // ------------------------------------------------------------ dragging

  property int dragTileId: -1
  property string dragSource: ""
  property real dragX: 0
  property real dragY: 0

  // Rearranging the rack is the player's own business: allowed whenever their
  // rack is showing, even while the other player (or the computer) moves.
  // Placing on the board waits for their turn (see endDrag).
  function beginDrag(tileId, source, sx, sy) {
    if (tileId < 0) return
    var rackOnly = source === "rack" && controller.isActive && !controller.handoverPending
    if (!controller.humanTurn && !rackOnly) return
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
    if (cell && controller.humanTurn && controller.cells[cell.row * 15 + cell.col].kind === "empty") {
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
    if (shortcut("save", event)) { c.persist(); c.say(tr("notice.saved"), "info"); return true }
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
          c.say(tr(typingDirection === "H" ? "notice.typingHorizontal" : "notice.typingVertical"), "info")
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
      confirmDialog.ask("newgame", tr("confirm.newGame.title"), tr("confirm.newGame.message"), tr("confirm.newGame.button"), true)
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
      else if (action === "resetStats") { view.saves.resetStats(); view.controller.say(tr("notice.statsReset"), "info") }
      if (view.overlay === "stats") statsScreen.forceActiveFocus()
      else keys.forceActiveFocus()
    }
    onCancelled: {
      open = false
      if (view.overlay === "stats") statsScreen.forceActiveFocus()
      else keys.forceActiveFocus()
    }
  }

  ConfirmDialog {
    id: moveConfirm
    theme: appTheme
    open: view.controller.confirmRequested
    title: tr("confirm.move.title")
    message: view.controller.preview ? tr("confirm.move.message", { words: view.controller.preview.words.map(function(w) { return (w.notation || w.word) + " " + w.score }).join(" · "), score: view.controller.preview.score }) : ""
    confirmText: tr("confirm.move.button")
    cancelText: tr("confirm.move.cancel")
    onConfirmed: { view.controller.confirmMove(); keys.forceActiveFocus() }
    onCancelled: { view.controller.cancelConfirm(); keys.forceActiveFocus() }
  }

  ChallengeDialog {
    theme: appTheme
    viewer: view.controller ? view.controller.viewer : 0
    open: view.controller.challengeOutcome !== null
    outcome: view.controller.challengeOutcome
    forms: view.controller.displayForms
    controller: view.controller
    dictionaryName: view.controller.game ? tr("dict." + (view.controller.game.dictionary.id || "open-fr") + ".label") : ""
    onClosed: { view.controller.dismissChallenge(); keys.forceActiveFocus() }
  }

  HandoverDialog {
    theme: appTheme
    open: view.screen === "game" && view.controller.handoverPending
    playerName: view.controller.game ? view.controller.playerLabel(view.controller.current) : ""
    lastMoveText: {
      var p = view.lastMovePreview()
      return p ? tr("handover.lastMove", { name: view.controller.playerLabel(view.controller.lastCommitted.player), word: p.words[0].word, score: p.score }) : ""
    }
    onReveal: { view.controller.revealRack(); keys.forceActiveFocus() }
  }

  WordDialog {
    id: wordDialog
    theme: appTheme
    definitions: view.definitions
    gameLanguage: view.controller ? view.controller.gameLanguage : "fr"
    forms: view.controller ? view.controller.displayForms : ({})
    onClosed: {
      open = false
      if (view.controller) { view.controller.highlightMove = -1; view.controller.revision++ }
      keys.forceActiveFocus()
    }
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
      { id: "new", text: tr("menu.newGame"), enabled: true },
      { id: "resign", text: tr("menu.resign"), enabled: view.controller.isActive },
      { id: "replay", text: tr("menu.replay"), enabled: !!(view.controller.game && view.controller.game.moves.length) },
      { id: "shortcuts", text: tr("menu.shortcuts"), enabled: true },
      { id: "about", text: tr("menu.about"), enabled: true }
    ]
    onActivated: function(id) {
      if (id === "new") view.askNewGame()
      else if (id === "resign") confirmDialog.ask("resign", tr("confirm.resign.title"), tr("confirm.resign.message"), tr("confirm.resign.button"), true)
      else if (id === "replay") view.replaying = true
      else if (id === "shortcuts") shortcutsDialog.open = true
      else if (id === "about") view.openSettings("about")
    }
  }

  // ------------------------------------------------------------ overlays

  EndScreen {
    anchors.fill: parent
    z: 60
    theme: appTheme
    controller: view.controller
    visible: !(view.controller.game && view.controller.game.end && view.controller.game.end.awaitingReveal) && view.screen === "game" && view.controller.isOver && !view.endDismissed && !view.replaying
    onNewGameRequested: view.screen = "setup"
    onReplayRequested: view.replaying = true
    onRematchRequested: view.startNewGame(view.settings.newGame ? Object.assign({}, view.settings.newGame, { difficulty: view.settings.ai.difficulty }) : {})
    onCloseRequested: view.endDismissed = true
    onWordRequested: function(moveIndex) { view.showMoveWords(moveIndex) }
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
    id: statsScreen
    anchors.fill: parent
    z: 70
    visible: view.overlay === "stats"
    theme: appTheme
    saves: view.saves
    onClosed: { view.overlay = ""; keys.forceActiveFocus() }
    onResetRequested: view.askResetStats()
  }

  SettingsScreen {
    id: settingsScreen
    anchors.fill: parent
    z: 70
    visible: view.overlay === "settings"
    theme: appTheme
    saves: view.saves
    dictionary: view.dictionary
    definitions: view.definitions
    online: view.online
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

  // Shown when the plugin on disk is newer than the code running in the
  // shell: keep-loaded panels only pick up new code on a shell restart.
  // An online game that stopped (a false tile, the copies disagree).
  Rectangle {
    z: 97
    visible: view.screen === "game" && !!view.controller && view.controller.isOnline && view.controller.onlineProblem !== null
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: appTheme.spaceSmall
    width: Math.min(parent.width - 2 * appTheme.padding, problemText.implicitWidth + 2 * appTheme.padding)
    height: problemText.implicitHeight + appTheme.padding
    radius: appTheme.radius
    color: appTheme.mix(appTheme.background, appTheme.urgent, 0.18)
    border.width: appTheme.borderWidth
    border.color: appTheme.alpha(appTheme.urgent, 0.7)
    Text {
      textFormat: Text.PlainText
      id: problemText
      anchors.centerIn: parent
      width: Math.min(implicitWidth, view.width - 4 * appTheme.padding)
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      readonly property var p: view.controller ? view.controller.onlineProblem : null
      text: !p ? "" : p.kind === "cheat" ? tr("online.banner.cheat") : p.kind === "desync" ? tr("online.banner.desync") : tr("online.banner.error", { message: p.message })
      color: appTheme.foreground
      font.family: appTheme.fontFamily
      font.pixelSize: appTheme.fontSmall
    }
  }

  property string runningVersion: ""
  property string installedVersion: ""
  Rectangle {
    id: updateBanner
    z: 96
    visible: view.runningVersion !== "" && view.installedVersion !== "" && view.runningVersion !== view.installedVersion
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: appTheme.spaceSmall
    width: Math.min(parent.width - 2 * appTheme.padding, bannerText.implicitWidth + 2 * appTheme.padding)
    height: bannerText.implicitHeight + appTheme.padding
    radius: appTheme.radius
    color: appTheme.panelStrong
    border.width: appTheme.borderWidth
    border.color: appTheme.alpha(appTheme.accent, 0.7)
    Text {
      textFormat: Text.PlainText
      id: bannerText
      anchors.centerIn: parent
      width: Math.min(implicitWidth, view.width - 4 * appTheme.padding)
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      text: tr("update.banner", { installed: view.installedVersion, running: view.runningVersion })
      color: appTheme.foreground
      font.family: appTheme.fontFamily
      font.pixelSize: appTheme.fontSmall
    }
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
      textFormat: Text.PlainText
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
    title: tr("saveProblem.title")
    message: view.saves && view.saves.problem
      ? (tr("save." + view.saves.problem.error) + "\n\n" + tr("saveProblem.kept") + "\n" + view.saves.problem.keptAs)
      : ""
    confirmText: tr("saveProblem.ok")
    cancelText: tr("common.close")
    onConfirmed: view.saves.dismissProblem()
    onCancelled: view.saves.dismissProblem()
  }

  onScreenChanged: Qt.callLater(function() { if (view.screen === "game") keys.forceActiveFocus() })
  Component.onCompleted: keys.forceActiveFocus()
}
