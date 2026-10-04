import QtQuick
import Quickshell
import Quickshell.Io
import "../engine/serializer.mjs" as Serializer
import "../engine/stats.mjs" as Stats
import "../app/settings.mjs" as SettingsModel

// Local persistence: the game in progress, settings and statistics, under
// $XDG_STATE_HOME/omascrabble (~/.local/state/omascrabble).
//
// Nothing is ever written inside the plugin directory: the shell reloads
// every plugin when a file changes there. Writes are atomic (temp file +
// rename) and blocking — they are a few kilobytes, and a blocking write is
// what lets the last save complete when the shell tears the panel down.
//
// Save files are untrusted input. A file that cannot be read back (corrupt,
// from a newer version…) is moved to quarantine/ with a timestamp, never
// deleted or overwritten, and `problem` tells the UI what happened.
Item {
  id: saves
  visible: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: {
    var x = Quickshell.env("XDG_STATE_HOME")
    return x && x.charAt(0) === "/" ? x : home + "/.local/state"
  }
  readonly property string stateDir: stateHome + "/omascrabble"
  readonly property string gamePath: stateDir + "/game.json"
  readonly property string settingsPath: stateDir + "/settings.json"
  readonly property string statsPath: stateDir + "/stats.json"

  property bool directoryReady: false
  property bool gameChecked: false
  property bool settingsChecked: false
  property bool statsChecked: false
  readonly property bool ready: directoryReady && gameChecked && settingsChecked && statsChecked

  property var settings: SettingsModel.normalizeSettings({})
  property var stats: Stats.emptyStats()
  property var savedGame: null      // engine state of the saved game, or null
  property var savedExtras: ({})    // UI extras stored with the game (rack order…)
  property var problem: null        // { file, error, message, detail, keptAs }
  property string lastError: ""

  signal settingsSaved()

  function timestamp() {
    var d = new Date()
    var pad = function(n) { return (n < 10 ? "0" : "") + n }
    return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + "-" + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds())
  }

  // Moves an unreadable file aside and records why.
  function quarantine(path, label, failure) {
    var name = path.split("/").pop().replace(/\.json$/, "")
    var target = stateDir + "/quarantine/" + name + "." + timestamp() + ".json"
    quarantineProc.command = ["sh", "-c", 'mkdir -p -- "$(dirname -- "$2")" && mv -f -- "$1" "$2"', "quarantine", path, target]
    quarantineProc.running = true
    problem = { file: label, error: failure.error || "CORRUPT", message: failure.message || "", detail: failure.detail || "", keptAs: target }
    console.warn("omascrabble: " + label + " could not be loaded (" + (failure.error || "?") + " " + (failure.detail || "") + "), kept as " + target)
  }

  function dismissProblem() { problem = null }

  // ---------------------------------------------------------------- writes

  function saveGame(state, extras) {
    if (!directoryReady || !state) return false
    try {
      var doc = JSON.parse(Serializer.serializeGame(state))
      doc.ui = extras && typeof extras === "object" ? extras : {}
      writeGameText(JSON.stringify(doc))
      savedGame = state
      savedExtras = doc.ui
      return true
    } catch (e) {
      lastError = String(e)
      console.warn("omascrabble: could not save the game:", e)
      return false
    }
  }

  function forgetGame() {
    if (!directoryReady) return
    savedGame = null
    savedExtras = ({})
    writeGameText("")
  }

  // While a bad save is being moved to quarantine, hold game writes back so
  // the move can never pick up the new file instead.
  property var heldGameText: null
  function writeGameText(text) {
    if (quarantineProc.running) { heldGameText = text; return }
    gameFile.setText(text)
  }

  function saveSettings(next) {
    settings = SettingsModel.normalizeSettings(next)
    if (directoryReady) settingsFile.setText(JSON.stringify(settings, null, 2))
    settingsSaved()
  }

  function saveStats(next) {
    stats = Stats.normalizeStats(next)
    if (directoryReady) statsFile.setText(JSON.stringify(stats))
  }

  function recordFinishedGame(state, me) {
    try {
      var summary = Stats.summarizeGame(state, me)
      saveStats(Stats.recordGame(stats, summary))
      archiveGame(state)
      return summary
    } catch (e) {
      console.warn("omascrabble: could not record statistics:", e)
      return null
    }
  }

  function archiveGame(state) {
    if (!directoryReady) return
    archiveFile.path = stateDir + "/archive/" + String(state.gameId).replace(/[^A-Za-z0-9_-]/g, "") + ".json"
    archiveFile.setText(Serializer.serializeGame(state))
  }

  // ----------------------------------------------------------------- reads

  function applyGameText(text) {
    var raw = String(text || "")
    if (raw.trim().length === 0) { savedGame = null; gameChecked = true; return }
    var result = Serializer.deserializeGame(raw)
    if (result.ok) {
      savedGame = result.state
      try {
        var doc = JSON.parse(raw)
        savedExtras = doc && doc.ui && typeof doc.ui === "object" ? doc.ui : ({})
      } catch (e) { savedExtras = ({}) }
    } else {
      savedGame = null
      quarantine(gamePath, "partie", result)
    }
    gameChecked = true
  }

  function applySettingsText(text) {
    var raw = String(text || "")
    if (raw.trim().length > 0) {
      try {
        settings = SettingsModel.normalizeSettings(JSON.parse(raw))
      } catch (e) {
        quarantine(settingsPath, "réglages", { error: "MALFORMED_JSON", message: "Les réglages étaient illisibles et ont été réinitialisés." })
      }
    }
    settingsChecked = true
  }

  function applyStatsText(text) {
    var raw = String(text || "")
    if (raw.trim().length > 0) {
      try {
        stats = Stats.normalizeStats(JSON.parse(raw))
      } catch (e) {
        quarantine(statsPath, "statistiques", { error: "MALFORMED_JSON", message: "Les statistiques étaient illisibles." })
      }
    }
    statsChecked = true
  }

  FileView {
    id: gameFile
    path: saves.directoryReady ? saves.gamePath : ""
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: saves.applyGameText(text())
    onLoadFailed: function(err) { saves.applyGameText("") }
    onSaveFailed: function(err) { saves.lastError = "save failed: " + err; console.warn("omascrabble: game save failed", err) }
  }

  FileView {
    id: settingsFile
    path: saves.directoryReady ? saves.settingsPath : ""
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: saves.applySettingsText(text())
    onLoadFailed: function(err) { saves.applySettingsText("") }
  }

  FileView {
    id: statsFile
    path: saves.directoryReady ? saves.statsPath : ""
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: saves.applyStatsText(text())
    onLoadFailed: function(err) { saves.applyStatsText("") }
  }

  FileView {
    id: archiveFile
    atomicWrites: true
    blockWrites: true
    printErrors: false
    preload: false
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", "--", saves.stateDir + "/archive"]
    onExited: function(code) {
      if (code !== 0) console.warn("omascrabble: cannot create " + saves.stateDir)
      saves.directoryReady = true
    }
  }

  Process {
    id: quarantineProc
    onExited: {
      if (saves.heldGameText !== null) {
        var text = saves.heldGameText
        saves.heldGameText = null
        gameFile.setText(text)
      }
    }
  }

  Component.onCompleted: mkdirProc.running = true
}
