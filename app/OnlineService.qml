import QtQuick
import Quickshell
import Quickshell.Io

// The online helper (net/online.py), started on demand and kept running
// while the plugin is loaded. Commands go out as JSON lines on its stdin,
// events come back on its stdout; everything coming back is treated as data
// and checked before use. See docs/ONLINE.md.
Item {
  id: service
  visible: false

  property string pluginDir: ""
  property string playerName: ""

  // "" until the helper answered; then "tox", "tcp" or "none" (toxcore
  // missing: online play unavailable).
  property string transport: ""
  readonly property bool checked: transport !== ""
  readonly property bool available: transport === "tox" || transport === "tcp"
  property bool pythonMissing: false

  // Invitation / join flow, for the online screen.
  property string stage: ""          // "", inviting, joining, proposal, dealing, playing, declined, failed
  property string link: ""
  property string gameId: ""
  property var proposal: null        // { config, from, gameId }
  property string peerName: ""
  property bool peerConnected: false
  property var lastError: null       // { code, message }

  signal event(var ev)

  property var queue: []

  function start() {
    if (!helper.running && pluginDir !== "") helper.running = true
  }

  function send(cmd) {
    if (helper.running && helper.ready) helper.write(JSON.stringify(cmd) + "\n")
    else { queue = queue.concat([cmd]); start() }
  }

  function hello() {
    send({ cmd: "hello", name: playerName })
  }

  function recheck() {
    transport = ""
    pythonMissing = false
    if (helper.running) { helper.ready = false; helper.signal(15) }
    else start()
    hello()
  }

  function invite(config) {
    lastError = null; link = ""; proposal = null; peerName = ""; peerConnected = false
    stage = "inviting"
    hello()
    send({ cmd: "invite", config: config })
  }

  function join(text, tiles) {
    lastError = null; link = ""; proposal = null; peerName = ""; peerConnected = false
    stage = "joining"
    hello()
    send({ cmd: "join", link: String(text).trim(), tiles: tiles })
  }

  function accept() { stage = "dealing"; send({ cmd: "accept" }) }
  function decline() { stage = ""; send({ cmd: "decline" }) }
  function cancel() { stage = ""; link = ""; proposal = null; send({ cmd: "cancel" }) }

  function resume(gameId, moves) {
    hello()
    send({ cmd: "resume", gameId: gameId, moves: moves })
  }

  function handle(ev) {
    if (!ev || typeof ev.ev !== "string") return
    switch (ev.ev) {
    case "ready":
      transport = ev.transport === "tox" || ev.transport === "tcp" ? ev.transport : "none"
      break
    case "invite":
      link = String(ev.link || "")
      gameId = String(ev.gameId || "")
      break
    case "peer":
      peerName = String(ev.name || "").slice(0, 40)
      peerConnected = true
      if (stage === "inviting") stage = "dealing"
      break
    case "proposal":
      proposal = { config: ev.config || {}, from: String(ev.from || "").slice(0, 40), gameId: String(ev.gameId || "") }
      stage = "proposal"
      break
    case "accepted":
      stage = "dealing"
      break
    case "declined":
      stage = "declined"
      break
    case "started":
      stage = "playing"
      break
    case "link":
      peerConnected = ev.state === "connected"
      break
    case "error":
      lastError = { code: String(ev.code || ""), message: String(ev.message || "").slice(0, 300) }
      if (stage === "inviting" || stage === "joining" || stage === "dealing") stage = "failed"
      break
    }
    service.event(ev)
  }

  Process {
    id: helper
    property bool ready: false
    // -B: no __pycache__ in the plugin folder (any change there makes
    // Omarchy reload the plugin and close the game).
    command: ["sh", "-c", 'command -v python3 >/dev/null 2>&1 || exit 127; exec python3 -B "$@"', "online", service.pluginDir + "/net/online.py"]
    stdinEnabled: true
    onStarted: {
      ready = true
      var pending = service.queue
      service.queue = []
      for (var i = 0; i < pending.length; i++) write(JSON.stringify(pending[i]) + "\n")
    }
    stdout: SplitParser {
      onRead: function(line) {
        if (line.length > 4000000) return
        var ev
        try { ev = JSON.parse(line) } catch (e) { return }
        service.handle(ev)
      }
    }
    stderr: SplitParser {
      onRead: function(line) { console.warn("omascrabble online:", String(line).slice(0, 300)) }
    }
    onExited: function(exitCode, exitStatus) {
      ready = false
      if (exitCode === 127) { service.pythonMissing = true; service.transport = "none"; service.queue = []; return }
      if (service.queue.length > 0) Qt.callLater(service.start)
    }
  }
}
