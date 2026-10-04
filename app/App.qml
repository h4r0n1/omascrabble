import QtQuick
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
    windowActive: app.windowVisible
  }

  SystemPreferences { id: systemPreferences }

  DefinitionsService { id: definitionsService }

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
