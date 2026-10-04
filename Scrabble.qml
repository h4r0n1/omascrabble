import QtQuick
import Quickshell
import qs.Commons

// Omarchy Scrabble — panel entry point.
//
// Runs inside the existing omarchy-shell (no second Quickshell instance).
// The host summons it with
//     omarchy-shell shell toggle omascrabble
// and calls open(payloadJson) / close(); `keepLoaded: true` in the manifest
// keeps this item, and the game in it, alive between summons.
//
// This file stays small on purpose: keep-loaded panels are created when the
// shell starts, so the game's services and UI are only built on first open.
// Both load through Loaders that act as error boundaries — if the game fails
// to load, a plain recovery card appears instead, and the shell carries on.
Item {
  id: root

  readonly property string selfId: "omascrabble"
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }

  property bool opened: false
  property bool everOpened: false
  property bool closingFromHost: false

  // Injected by the host.
  property var shell: null
  property var manifest: null

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    closingFromHost = false
    everOpened = true
    opened = true
    if (appLoader.item) appLoader.item.preferences.refresh()
    Qt.callLater(function() { if (viewLoader.item) viewLoader.item.forceActiveFocus() })
  }

  // Host-initiated hide: the host already knows.
  function close() {
    closingFromHost = true
    opened = false
    if (appLoader.item) appLoader.item.flush()
    closingFromHost = false
  }

  // User-initiated close (window closed by the compositor).
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(selfId)
    else close()
  }

  function toggle() {
    if (opened) requestClose()
    else open("{}")
  }

  // ------------------------------------------------------- IPC helpers
  // omarchy-shell shell call omascrabble status ""
  function status(arg) {
    var app = appLoader.item
    return app ? app.controller.statusJson() : JSON.stringify({ loaded: false })
  }

  // Saves a picture of the game window to $XDG_RUNTIME_DIR (fixed name) and
  // returns the path — for bug reports and testing.
  function snapshot(arg) {
    var dir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    var path = dir + "/omascrabble-snapshot.png"
    if (!content.visible) return "hidden"
    content.grabToImage(function(result) { result.saveToFile(path) })
    return path
  }

  // ------------------------------------------------------------- services

  Loader {
    id: appLoader
    active: root.everOpened
    source: "app/App.qml"
    onLoaded: {
      item.pluginDir = root.pluginDir
      item.windowVisible = Qt.binding(function() { return root.opened })
    }
    onStatusChanged: if (status === Loader.Error) console.warn("omascrabble: services failed to load")
  }

  // ---------------------------------------------------------------- window

  FloatingWindow {
    id: window
    title: "Scrabble"
    visible: root.opened
    implicitWidth: 1180
    implicitHeight: 860
    minimumSize: Qt.size(560, 620)
    color: Color.background

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.opened) root.requestClose()
    }
    onClosed: if (root.opened) root.requestClose()

    Item {
      id: content
      anchors.fill: parent

      Loader {
        id: viewLoader
        anchors.fill: parent
        active: root.everOpened && appLoader.status === Loader.Ready
        source: "components/GameView.qml"
        focus: true
        onLoaded: {
          var app = appLoader.item
          item.controller = app.controller
          item.saves = app.saves
          item.dictionary = app.dictionary
          item.sounds = app.sounds
          item.systemPrefersDark = Qt.binding(function() { return app.preferences.prefersDark })
          item.systemReducedMotion = Qt.binding(function() { return app.preferences.reducedMotion })
          item.windowVisible = Qt.binding(function() { return root.opened })
          item.closeRequested.connect(root.requestClose)
          item.forceActiveFocus()
        }
      }

      // Error boundary: shown if the game UI or its services fail to load.
      Rectangle {
        anchors.fill: parent
        visible: viewLoader.status === Loader.Error || appLoader.status === Loader.Error
        color: Color.background
        Column {
          anchors.centerIn: parent
          width: Math.min(560, parent.width - 48)
          spacing: 14
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Le jeu n’a pas pu démarrer"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            font.bold: true
          }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Une erreur empêche le chargement de l’interface. Le shell n’est pas affecté et votre partie sauvegardée est intacte. "
              + "Une mise à jour d’Omarchy ou du plugin peut en être la cause : essayez « omarchy plugin update omascrabble »."
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.7)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Text {
            width: parent.width
            wrapMode: Text.WrapAnywhere
            text: viewLoader.status === Loader.Error && viewLoader.sourceComponent ? viewLoader.sourceComponent.errorString() : ""
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Rectangle {
            width: retryLabel.implicitWidth + 28
            height: retryLabel.implicitHeight + 14
            radius: Style.cornerRadius
            color: Color.accent
            Text {
              id: retryLabel
              anchors.centerIn: parent
              text: "Réessayer"
              color: Color.background
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                viewLoader.active = false
                Qt.callLater(function() { viewLoader.active = Qt.binding(function() { return root.everOpened && appLoader.status === Loader.Ready }) })
              }
            }
          }
        }
      }
    }
  }
}
