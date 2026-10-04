import QtQuick
import Quickshell.Io

// Desktop preferences the game follows: the freedesktop colour scheme (which
// Omarchy sets when switching themes) and whether animations are wanted.
// Read with gsettings when available; sensible defaults otherwise.
Item {
  id: prefs
  visible: false

  property bool prefersDark: true
  property bool reducedMotion: false

  function refresh() { probe.running = true }

  Process {
    id: probe
    command: ["sh", "-c", "command -v gsettings >/dev/null 2>&1 || exit 0; gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null; gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        if (lines.length > 0 && lines[0].indexOf("'") !== -1) prefs.prefersDark = lines[0].indexOf("light") === -1
        if (lines.length > 1 && lines[1].trim() !== "") prefs.reducedMotion = lines[1].trim() === "false"
      }
    }
  }

  Component.onCompleted: refresh()
}
