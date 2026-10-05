import QtQuick
import ".."
import "../../app/format.mjs" as Format

// Welcome: resume the saved game or start a new one.
FocusScope {
  id: home

  property var theme
  property var controller
  property var saves
  property var dictionary

  signal resumeRequested()
  signal newGameRequested()
  signal statsRequested()
  signal settingsRequested()

  readonly property var saved: saves ? saves.savedGame : null
  readonly property bool canResume: !!saved && saved.status === "active"
  readonly property real tileSize: Math.max(30, Math.min(58, (width - 2 * theme.padding) / 11))

  function tr(key, args) { return theme.t(key, args) }

  // Same labelling rules as the controller (default names follow the
  // interface language), for a saved game the controller hasn't loaded.
  function nameOf(g, index) {
    var p = g.players[index]
    var defaults = ["", "Vous", "Ordinateur", "Ordinateur 1", "Ordinateur 2", "Joueur 1", "Joueur 2", "You", "Computer", "Computer 1", "Computer 2", "Player 1", "Player 2"]
    if (defaults.indexOf(p.name) === -1) return p.name
    if (p.kind === "ai") return g.players.filter(function(q) { return q.kind === "ai" }).length > 1 ? tr("player.computerN", { n: index + 1 }) : tr("player.computer")
    return g.mode === "human_vs_human" ? tr("player.defaultName", { n: index + 1 }) : tr("player.you")
  }

  function modeLabel(g) {
    if (!g) return ""
    if (g.mode === "human_vs_ai") {
      var ai = g.players.filter(function(p) { return p.kind === "ai" })[0]
      return tr("mode.human_vs_ai") + (ai ? " · " + tr("difficulty." + (ai.difficulty || "casual")) : "")
    }
    return tr("mode." + g.mode)
  }

  function scoreLine(g) {
    if (!g) return ""
    return g.players.map(function(p, i) { return home.nameOf(g, i) + tr("common.colon") + p.score }).join("   ·   ")
  }

  Keys.onReturnPressed: canResume ? resumeRequested() : newGameRequested()
  Keys.onEnterPressed: canResume ? resumeRequested() : newGameRequested()
  Keys.onPressed: function(event) {
    if (event.text === "n" || event.text === "N") { newGameRequested(); event.accepted = true }
  }

  Flickable {
    anchors.fill: parent
    contentHeight: Math.max(height, column.implicitHeight + 2 * home.theme.spaceHuge)
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: column
      width: Math.min(560, parent.width - 2 * home.theme.padding)
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(home.theme.spaceHuge, (parent.height - implicitHeight) / 2.4)
      spacing: home.theme.spaceHuge

      // The title, set in tiles: a smaller OMA centred above SCRABBLE.
      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(home.tileSize * 0.14)
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Math.round(home.tileSize * 0.1)
          Repeater {
            model: [["O", 1], ["M", 2], ["A", 1]]
            Tile {
              required property var modelData
              required property int index
              theme: home.theme
              size: Math.round(home.tileSize * 0.62)
              letter: modelData[0]
              points: modelData[1]
              rotation: [1.5, -1, 2][index]
              y: [1, -1, 0][index]
            }
          }
        }
        Row {
          spacing: Math.round(home.tileSize * 0.12)
          Repeater {
            model: [["S", 1], ["C", 3], ["R", 1], ["A", 1], ["B", 3], ["B", 3], ["L", 1], ["E", 1]]
            Tile {
              required property var modelData
              required property int index
              theme: home.theme
              size: home.tileSize
              letter: modelData[0]
              points: modelData[1]
              rotation: [-2, 1.5, -1, 2, -1.5, 1, -2, 1.5][index]
              y: [0, 3, -2, 2, 0, -3, 2, 0][index]
            }
          }
        }
      }

      Rectangle {
        visible: home.canResume
        width: parent.width
        height: resumeColumn.implicitHeight + 2 * home.theme.padding
        radius: home.theme.radius
        color: home.theme.panel
        border.width: home.theme.borderWidth
        border.color: home.theme.line
        Column {
          id: resumeColumn
          x: home.theme.padding
          y: home.theme.padding
          width: parent.width - 2 * home.theme.padding
          spacing: home.theme.space
          Text {
            text: home.tr("home.inProgress")
            color: home.theme.muted
            font.family: home.theme.fontFamily
            font.pixelSize: home.theme.fontCaption
            font.weight: Font.Bold
            font.letterSpacing: 1.2
          }
          Text {
            text: home.modeLabel(home.saved)
            color: home.theme.foreground
            font.family: home.theme.fontFamily
            font.pixelSize: home.theme.fontTitle
            font.weight: Font.Bold
          }
          Text {
            text: home.scoreLine(home.saved) + (home.saved ? "   ·   " + home.tr("home.turn", { n: home.saved.turn }) + "   ·   " + home.tr("common.tilesInBag", { n: home.saved.bag.length }) : "")
            color: home.theme.muted
            font.family: home.theme.fontFamily
            font.pixelSize: home.theme.fontSmall
            width: parent.width
            wrapMode: Text.WordWrap
          }
          GameButton {
            theme: home.theme
            variant: "primary"
            text: home.tr("home.resume")
            icon: "play"
            onClicked: home.resumeRequested()
          }
        }
      }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: home.theme.space
        GameButton {
          anchors.horizontalCenter: parent.horizontalCenter
          theme: home.theme
          variant: home.canResume ? "secondary" : "primary"
          text: home.tr("home.newGame")
          icon: "plus"
          onClicked: home.newGameRequested()
        }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: home.theme.space
          GameButton { theme: home.theme; variant: "ghost"; text: home.tr("home.stats"); icon: "stats"; onClicked: home.statsRequested() }
          GameButton { theme: home.theme; variant: "ghost"; text: home.tr("home.settings"); icon: "settings"; onClicked: home.settingsRequested() }
        }
      }

      Column {
        width: parent.width
        spacing: 4
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: home.dictionary && home.dictionary.provider
            ? home.tr("dict." + home.dictionary.provider.id() + ".label") + "  ·  " + home.tr("home.words", { n: Format.formatInt(home.dictionary.provider.graph().wordCount) })
            : ""
          color: home.theme.muted
          font.family: home.theme.fontFamily
          font.pixelSize: home.theme.fontSmall
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: home.tr("home.disclaimer")
          color: home.theme.alpha(home.theme.muted, 0.8)
          font.family: home.theme.fontFamily
          font.pixelSize: home.theme.fontCaption
        }
      }
    }
  }
}
