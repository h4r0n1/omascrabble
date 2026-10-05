import QtQuick
import Quickshell
import Quickshell.Io
import "dawg.mjs" as Dawg
import "registry.mjs" as Registry

// Loads a dictionary for the game without ever blocking the shell.
//
// The file is read asynchronously, then decoded and validated on this
// thread in slices of a few milliseconds (DawgLoader), so the bar never
// stutters. The same text goes to the AI worker, which decodes its own copy
// on its own thread. Dictionary files are data: parsed and checked, never
// executed or imported.
//
// Bundled data lives in the plugin (dictionary/data); installed data, such as
// a licensed ODS 9, in $XDG_DATA_HOME/omascrabble/dictionaries.
Item {
  id: service
  visible: false

  property string pluginDir: ""
  property var worker: null                 // WorkerScript that hosts the AI

  readonly property string userDictionaryDir: {
    var x = Quickshell.env("XDG_DATA_HOME")
    return (x && x.charAt(0) === "/" ? x : Quickshell.env("HOME") + "/.local/share") + "/omascrabble/dictionaries"
  }

  property string dictionaryId: ""
  property string status: "idle"            // idle | loading | ready | missing | error
  property string errorMessage: ""
  property real progress: 0
  property var provider: null
  property bool workerReady: false
  property string workerDictionaryId: ""
  property bool formsSent: false

  // Which dictionaries exist on this machine, for the setup screen.
  property var installed: ({ "open-fr": true })
  readonly property var choices: Registry.DICTIONARIES.map(function(d) {
    return { id: d.id, language: d.language, official: d.official, available: service.installed[d.id] === true }
  })

  signal ready()
  signal failed(string message)

  function fileFor(entry, forms) {
    var rel = forms ? entry.formsFile : entry.file
    return entry.location === "bundled" ? pluginDir + "/" + rel : userDictionaryDir + "/" + rel
  }

  function load(id) {
    var entry = Registry.dictionaryEntry(id) || Registry.dictionaryEntry(Registry.DEFAULT_DICTIONARY_ID)
    if (status === "ready" && dictionaryId === entry.id) return
    if (status === "loading" && dictionaryId === entry.id) return
    stepper.stop()
    loader = null
    provider = null
    formsSent = false
    dictionaryId = entry.id
    status = "loading"
    progress = 0
    errorMessage = ""
    dictFile.path = ""
    dictFile.path = fileFor(entry, false)
  }

  function retry() {
    var id = dictionaryId || Registry.DEFAULT_DICTIONARY_ID
    status = "idle"
    load(id)
  }

  property var loader: null
  property string pendingText: ""

  function begin(text) {
    try {
      loader = new Dawg.DawgLoader(text)
      if (loader.decoder.header.id !== dictionaryId) throw new Error("le fichier ne contient pas le dictionnaire attendu (" + loader.decoder.header.id + ")")
    } catch (e) {
      fail(e)
      return
    }
    sendToWorker(text)
    stepper.start()
  }

  function sendToWorker(text) {
    if (!worker) return
    workerReady = false
    worker.sendMessage({ type: "init", dictId: dictionaryId, text: text })
  }

  function fail(e) {
    stepper.stop()
    loader = null
    status = "error"
    errorMessage = e && e.message ? String(e.message) : String(e)
    console.warn("omascrabble: dictionary " + dictionaryId + " failed:", errorMessage)
    failed(errorMessage)
  }

  // Accented spellings are only needed for display, so they load on demand
  // and only into the worker.
  function ensureDisplayForms() {
    if (formsSent || !worker || status !== "ready") return
    var entry = Registry.dictionaryEntry(dictionaryId)
    if (!entry) return
    formsSent = true
    formsFile.path = fileFor(entry, true)
  }

  function onWorkerMessage(message) {
    if (message.type === "ready") {
      workerReady = true
      workerDictionaryId = String(message.dictId || "")
    } else if (message.type === "error" && message.stage === "init") {
      workerReady = false
      console.warn("omascrabble: AI worker could not load the dictionary:", message.message)
    }
  }

  Timer {
    id: stepper
    interval: 1
    repeat: true
    onTriggered: {
      if (!service.loader) { stop(); return }
      var started = Date.now()
      try {
        // Keep each slice to roughly 6 ms of work.
        while (Date.now() - started < 6) {
          if (service.loader.step(24000)) {
            stop()
            var dawg = service.loader.dawg
            service.loader = null
            service.provider = Registry.createProvider(service.dictionaryId, dawg, null)
            service.progress = 1
            service.status = "ready"
            service.ready()
            return
          }
        }
        service.progress = service.loader.progress
      } catch (e) {
        service.fail(e)
      }
    }
  }

  FileView {
    id: dictFile
    printErrors: false
    onLoaded: service.begin(text())
    onLoadFailed: function(err) {
      if (service.status !== "loading") return
      service.status = "missing"
      service.errorMessage = "Fichier introuvable : " + path
      service.failed(service.errorMessage)
    }
  }

  FileView {
    id: formsFile
    printErrors: false
    onLoaded: if (service.worker) service.worker.sendMessage({ type: "forms", text: text() })
    onLoadFailed: function(err) { console.warn("omascrabble: display forms unavailable") }
  }

  // Detect a user-installed ODS 9 without keeping its contents around.
  Process {
    id: probe
    command: ["sh", "-c", 'for f in "$@"; do [ -r "$f" ] && echo "$f"; done; true', "probe", service.userDictionaryDir + "/ods9.dawg"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = { "open-fr": true }
        if (String(text).indexOf("ods9.dawg") !== -1) next["ods9"] = true
        service.installed = next
      }
    }
  }

  function refreshInstalled() { probe.running = true }
  Component.onCompleted: refreshInstalled()
}
