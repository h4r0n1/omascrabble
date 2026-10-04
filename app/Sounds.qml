import QtQuick

// Optional sound effects. The QtMultimedia part lives in SoundBank.qml and is
// loaded only when sounds are switched on, so a system without QtMultimedia
// simply has no sounds — the game itself never depends on it.
Item {
  id: sounds
  visible: false

  property bool enabled: false
  property string baseDir: ""
  property bool unavailable: false

  function play(name) {
    if (!enabled || unavailable || !bank.item) return
    bank.item.play(name)
  }

  Loader {
    id: bank
    active: sounds.enabled
    source: "SoundBank.qml"
    onLoaded: item.baseDir = sounds.baseDir
    onStatusChanged: {
      if (status === Loader.Error) {
        sounds.unavailable = true
        console.warn("omascrabble: sounds unavailable (QtMultimedia missing?)")
      }
    }
  }
}
