import QtQuick
import Quickshell
import Quickshell.Io
import "normalize.mjs" as Normalize

// Optional word definitions (Wiktionary, CC BY-SA 4.0), installed per game
// language by tools/install-definitions.py into
// $XDG_DATA_HOME/omascrabble/definitions/<lang> as small JSON shards. Shards are read on demand, asynchronously, and treated
// as untrusted data: parsed, checked, never executed. Without the pack the
// game simply says how to install it.
Item {
  id: service
  visible: false

  // Language of the words being looked up: the game's, not the interface's.
  property string language: "fr"
  readonly property string packDir: {
    var x = Quickshell.env("XDG_DATA_HOME")
    return (x && x.charAt(0) === "/" ? x : Quickshell.env("HOME") + "/.local/share") + "/omascrabble/definitions/" + (language === "en" ? "en" : "fr")
  }
  onPackDirChanged: {
    cache = ({})
    queue = []
    waiting = ({})
    checked = false
    installed = false
    manifest = null
  }

  property bool checked: false
  property bool installed: false
  property var manifest: null
  property var cache: ({})          // prefix → shard object
  property var queue: []            // prefixes waiting to load
  property var waiting: ({})        // prefix → [callbacks]

  function refresh() { manifestFile.reload() }

  function prefixOf(folded) { return folded.slice(0, 2) }

  function sanitizeEntries(list) {
    if (!Array.isArray(list)) return []
    var out = []
    for (var i = 0; i < list.length && i < 12; i++) {
      var e = list[i]
      if (!e || typeof e.w !== "string" || !Array.isArray(e.d)) continue
      var defs = e.d.filter(function(d) { return typeof d === "string" }).slice(0, 4).map(function(d) { return d.slice(0, 400) })
      if (!defs.length) continue
      out.push({ w: e.w.slice(0, 40), p: typeof e.p === "string" ? e.p.slice(0, 40) : "", d: defs, of: typeof e.of === "string" ? e.of.slice(0, 40) : "" })
    }
    return out
  }

  function withShard(prefix, callback) {
    if (cache[prefix] !== undefined) { callback(cache[prefix]); return }
    var w = Object.assign({}, waiting)
    var list = (w[prefix] || []).slice()
    list.push(callback)
    w[prefix] = list
    waiting = w
    if (queue.indexOf(prefix) === -1 && shardFile.loadingPrefix !== prefix) {
      queue = queue.concat([prefix])
      Qt.callLater(service.pump)
    }
  }

  function pump() {
    if (shardFile.loadingPrefix !== "" || queue.length === 0) return
    var next = queue[0]
    queue = queue.slice(1)
    shardFile.loadingPrefix = next
    shardFile.loadingDir = packDir
    shardFile.path = ""
    shardFile.path = packDir + "/" + next + ".json"
  }

  function finish(prefix, data) {
    if (shardFile.loadingDir !== packDir) {
      // Read for a language that is no longer current: drop it.
      shardFile.loadingPrefix = ""
      Qt.callLater(service.pump)
      return
    }
    var c = Object.assign({}, cache)
    c[prefix] = data
    cache = c
    var callbacks = waiting[prefix] || []
    var w = Object.assign({}, waiting)
    delete w[prefix]
    waiting = w
    shardFile.loadingPrefix = ""
    for (var i = 0; i < callbacks.length; i++) {
      try { callbacks[i](data) } catch (e) { console.warn("omascrabble: definitions callback failed:", e) }
    }
    // Start the next read outside this FileView's own signal handler.
    Qt.callLater(service.pump)
  }

  // callback({ installed, word, entries: [...], lemmas: { lemma: [...] } })
  function lookup(word, callback) {
    var folded = Normalize.foldWord(word)
    if (!installed || !folded) { callback({ installed: installed, word: word, entries: [], lemmas: {} }); return }
    withShard(prefixOf(folded), function(shard) {
      var entries = sanitizeEntries(shard ? shard[folded] : null)
      var lemmas = {}
      var pendingLemmas = []
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].of && pendingLemmas.indexOf(entries[i].of) === -1) pendingLemmas.push(entries[i].of)
      }
      if (!pendingLemmas.length) { callback({ installed: true, word: word, entries: entries, lemmas: lemmas }); return }
      var left = pendingLemmas.length
      pendingLemmas.forEach(function(lemma) {
        var lf = Normalize.foldWord(lemma)
        if (!lf) { if (--left === 0) callback({ installed: true, word: word, entries: entries, lemmas: lemmas }); return }
        withShard(prefixOf(lf), function(s2) {
          lemmas[lemma] = sanitizeEntries(s2 ? s2[lf] : null).filter(function(e) { return !e.of && e.w === lemma }).slice(0, 2)
          if (--left === 0) callback({ installed: true, word: word, entries: entries, lemmas: lemmas })
        })
      })
    })
  }

  FileView {
    id: manifestFile
    path: service.packDir + "/manifest.json"
    printErrors: false
    onLoaded: {
      try {
        var m = JSON.parse(text())
        service.installed = !!m && m.format === "omascrabble-definitions" && m.version === 1
          && (m.language === undefined || m.language === service.language)
        service.manifest = service.installed ? m : null
      } catch (e) {
        service.installed = false
      }
      service.checked = true
    }
    onLoadFailed: function(err) { service.installed = false; service.checked = true }
  }

  FileView {
    id: shardFile
    property string loadingPrefix: ""
    property string loadingDir: ""
    printErrors: false
    onLoaded: {
      var data = {}
      try {
        var parsed = JSON.parse(text())
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) data = parsed
      } catch (e) {
        console.warn("omascrabble: unreadable definitions shard", path)
      }
      service.finish(loadingPrefix, data)
    }
    onLoadFailed: function(err) { service.finish(loadingPrefix, {}) }
  }
}
