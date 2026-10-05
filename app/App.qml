import QtQuick
import Quickshell
import "../storage"
import "../dictionary"
import "../controller"

// The game's non-visual services, wired together: persistence, dictionary,
// the AI worker thread, the game controller, desktop preferences and sounds.
// Created on first open, then kept while the plugin is loaded.
Item {
  id: app
  visible: false

  property string pluginDir: ""
  property bool windowVisible: false

  readonly property alias saves: saveManager
  readonly property alias dictionary: dictionaryService
  readonly property alias controller: gameController
  readonly property alias preferences: systemPreferences
  readonly property alias sounds: soundPlayer
  readonly property alias definitions: definitionsService
  readonly property alias online: onlineService

  SaveManager {
    id: saveManager
    onReadyChanged: if (ready) app.boot()
  }

  WorkerScript {
    id: worker
    source: "../ai/worker.mjs"
    onMessage: function(message) {
      dictionaryService.onWorkerMessage(message)
      gameController.onWorkerMessage(message)
    }
  }

  DictionaryService {
    id: dictionaryService
    pluginDir: app.pluginDir
    worker: worker
  }

  GameController {
    id: gameController
    dictionary: dictionaryService
    saves: saveManager
    worker: worker
    online: onlineService
    windowActive: app.windowVisible
  }

  OnlineService {
    id: onlineService
    pluginDir: app.pluginDir
    playerName: saveManager.settings.online.name || systemUser
    readonly property string systemUser: {
      var u = Quickshell.env("USER") || ""
      return u ? u.charAt(0).toUpperCase() + u.slice(1) : ""
    }
    onEvent: function(ev) { gameController.onOnlineEvent(ev) }
    onFriendsKnown: if (!saveManager.settings.online.knownFriends)
      saveManager.saveSettings(Object.assign({}, saveManager.settings, { online: Object.assign({}, saveManager.settings.online, { knownFriends: true }) }))
  }

  // With friends and invitations on, be reachable while the game is loaded.
  Connections {
    target: saveManager
    function onReadyChanged() {
      var o = saveManager.settings.online
      if (saveManager.ready && o.listen && o.knownFriends) onlineService.hello()
    }
  }

  // An online game carries on in the background: reconnect as soon as the
  // word list is ready, so the other player's moves arrive even before the
  // game screen is opened.
  Connections {
    target: dictionaryService
    function onReady() {
      var saved = saveManager.savedGame
      if (saved && saved.mode === "online" && saved.status === "active" && !gameController.hasGame)
        gameController.resume(saved, saveManager.savedExtras)
    }
  }

  SystemPreferences { id: systemPreferences }

  DefinitionsService { id: definitionsService; language: gameController.gameLanguage; pluginDir: app.pluginDir }

  Sounds {
    id: soundPlayer
    enabled: saveManager.settings.gameplay.sounds
    baseDir: app.pluginDir + "/assets/sounds"
  }

  // Once saves are read: load the dictionary the saved game used (or the
  // preferred one) so resuming is instant.
  function boot() {
    var saved = saveManager.savedGame
    var id = saved && saved.dictionary && saved.dictionary.id ? saved.dictionary.id : saveManager.settings.newGame.dictionary
    dictionaryService.load(id)
  }

  function flush() {
    gameController.flushClock()
    gameController.persist()
  }

  Component.onDestruction: flush()
}
