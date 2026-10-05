import QtQuick
import Quickshell
import Quickshell.Io
import "normalize.mjs" as Normalize

// Optional word definitions (Wiktionary, CC BY-SA 4.0), installed per game
// language by tools/download-definitions.py into
// $XDG_DATA_HOME/omascrabble/definitions/<lang> as small JSON shards. Shards
// are read on demand, asynchronously, and treated as untrusted data: parsed,
// checked, never executed.
//
// The service also installs and removes packs: it runs the same script with
// --progress-json (one download at a time) and keeps running while the
// window is hidden.
Item {
  id: service
  visible: false

  property string pluginDir: ""
  // Language of the words being looked up: the game's, not the interface's.
  property string language: "fr"
  readonly property var languages: ["fr", "en"]
  readonly property string baseDir: {
    var x = Quickshell.env("XDG_DATA_HOME")
    return (x && x.charAt(0) === "/" ? x : Quickshell.env("HOME") + "/.local/share") + "/omascrabble/definitions"
  }
  function dirFor(lang) { return baseDir + "/" + (lang === "en" ? "en" : "fr") }
  readonly property string packDir: dirFor(language)
  onPackDirChanged: clearCache()

  // lang → manifest of the installed pack, or null; checked[lang] once read.
  property var packs: ({})
  property var packsChecked: ({})
  readonly property bool checked: packsChecked[language] === true
  readonly property bool installed: !!packs[language]
  readonly property var manifest: packs[language] || null

  // The running (or last) download:
  //   { language, stage: preparing|downloading|writing|done|error|cancelled,
  //     done, total, kept, error: { code, message } }
  property var job: null
  readonly property bool busy: installer.running || remover.running
  signal installFinished(string language, bool ok)

  function clearCache() {
    cache = ({})
    queue = []
    waiting = ({})
  }

  function setPack(lang, manifest) {
    var p = Object.assign({}, packs)
    p[lang] = manifest
    packs = p
    var c = Object.assign({}, packsChecked)
    c[lang] = true
    packsChecked = c
  }

  function install(lang) {
    if (busy || !pluginDir) return false
    job = { language: lang, stage: "preparing", done: 0, total: 0, kept: 0, error: null }
    installer.lastError = null
    installer.cancelled = false
    installer.command = ["sh", "-c", 'command -v python3 >/dev/null 2>&1 || exit 127; exec python3 "$@"', "install",
                         pluginDir + "/tools/download-definitions.py", "--lang", lang, "--progress-json"]
    installer.running = true
    return true
  }

  function cancelInstall() {
    if (!installer.running) return
    installer.cancelled = true
    installer.signal(15) // SIGTERM: the script removes its temporary files
  }

  function remove(lang) {
    if (busy) return false
    remover.language = lang
    remover.command = ["rm", "-rf", "--", dirFor(lang)]
    remover.running = true
    return true
  }

  function updateJob(fields) {
    job = Object.assign({}, job || {}, fields)
  }

  property var cache: ({})          // prefix → shard object
  property var queue: []            // prefixes waiting to load
  property var waiting: ({})        // prefix → [callbacks]

  function refresh() {
    frManifest.reload()
    enManifest.reload()
  }

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

  // One manifest reader per language.
  component ManifestFile: FileView {
    property string lang: ""
    path: service.dirFor(lang) + "/manifest.json"
    printErrors: false
    onLoaded: {
      var m = null
      try {
        var parsed = JSON.parse(text())
        if (parsed && parsed.format === "omascrabble-definitions" && parsed.version === 1
            && (parsed.language === undefined || parsed.language === lang)) m = parsed
      } catch (e) {}
      service.setPack(lang, m)
    }
    onLoadFailed: function(err) { service.setPack(lang, null) }
  }
  ManifestFile { id: frManifest; lang: "fr" }

  // Version 0.1 kept the (French-only) pack directly in definitions/. Move it
  // into definitions/fr once, without deleting anything; resumes if a
  // previous move was interrupted.
  Process {
    id: legacyMigration
    command: ["sh", "-c", [
      'd="$1"; tmp="$d/.migrate-fr"',
      '[ -e "$d/fr" ] && exit 0',
      'if [ ! -d "$tmp" ]; then',
      '  [ -f "$d/manifest.json" ] || exit 0',
      '  grep -q \'"omascrabble-definitions"\' "$d/manifest.json" || exit 0',
      '  grep -q \'"language": *"en"\' "$d/manifest.json" && exit 0',
      '  mkdir -- "$tmp" || exit 1',
      'fi',
      'find "$d" -maxdepth 1 -type f -name "*.json" -exec mv -t "$tmp" -- {} + || exit 1',
      'mv -T -- "$tmp" "$d/fr" && echo migrated'
    ].join("\n"), "migrate", service.baseDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text).indexOf("migrated") !== -1) console.log("omascrabble: moved the French definitions into " + service.dirFor("fr"))
    }
    onExited: function(exitCode, exitStatus) { service.refresh() }
  }
  Component.onCompleted: legacyMigration.running = true
  ManifestFile { id: enManifest; lang: "en" }

  Process {
    id: installer
    property var lastError: null
    property bool cancelled: false
    stdout: SplitParser {
      onRead: function(line) {
        var e
        try { e = JSON.parse(line) } catch (err) { return }
        if (!e || typeof e.event !== "string") return
        if (e.event === "start") service.updateJob({ stage: "downloading", total: Number(e.total) || 0 })
        else if (e.event === "progress") service.updateJob({ stage: "downloading", done: Number(e.done) || 0, total: Number(e.total) || 0, kept: Number(e.kept) || 0 })
        else if (e.event === "writing") service.updateJob({ stage: "writing", kept: Number(e.kept) || 0 })
        else if (e.event === "done") service.updateJob({ stage: "done", kept: Number(e.entries) || 0 })
        else if (e.event === "error") installer.lastError = { code: String(e.code || "other"), message: String(e.message || "").slice(0, 300) }
      }
    }
    stderr: SplitParser {
      onRead: function(line) { if (String(line).indexOf("error") === 0) installer.lastErrorLine = String(line).slice(0, 300) }
    }
    property string lastErrorLine: ""
    onExited: function(exitCode, exitStatus) {
      var lang = service.job ? service.job.language : ""
      var ok = exitCode === 0
      if (ok) {
        service.updateJob({ stage: "done" })
        service.clearCache()
      } else if (installer.cancelled) {
        service.updateJob({ stage: "cancelled" })
      } else {
        var error = installer.lastError
          || (exitCode === 127 ? { code: "python", message: "" } : { code: "other", message: installer.lastErrorLine || ("exit " + exitCode) })
        service.updateJob({ stage: "error", error: error })
      }
      service.refresh()
      service.installFinished(lang, ok)
    }
  }

  Process {
    id: remover
    property string language: ""
    onExited: function(exitCode, exitStatus) {
      if (remover.language === service.language) service.clearCache()
      service.refresh()
    }
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
