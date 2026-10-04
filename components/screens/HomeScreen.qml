import QtQuick
import ".."
import "../../app/format.mjs" as Format
import "../../ai/difficulty.mjs" as Difficulty

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

  function modeLabel(g) {
    if (!g) return ""
    if (g.mode === "human_vs_ai") {
      var ai = g.players.filter(function(p) { return p.kind === "ai" })[0]
      return "Contre l’ordinateur" + (ai ? " · " + (Difficulty.DIFFICULTY_LABELS[ai.difficulty] || "") : "")
    }
    if (g.mode === "human_vs_human") return "Deux joueurs locaux"
    if (g.mode === "ai_vs_ai") return "Démonstration"
    return "Entraînement"
  }

  function scoreLine(g) {
    if (!g) return ""
    return g.players.map(function(p) { return p.name + "\u00a0: " + p.score }).join("   ·   ")
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

      // The title, set in tiles: a smaller OMA laid above SCRABBLE, flush
      // with its first letter, like a prefix placed on the board.
      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(home.tileSize * 0.14)
        Row {
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
            text: "PARTIE EN COURS"
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
            text: home.scoreLine(home.saved) + (home.saved ? "   ·   tour " + home.saved.turn + "   ·   " + home.saved.bag.length + " lettres dans le sac" : "")
            color: home.theme.muted
            font.family: home.theme.fontFamily
            font.pixelSize: home.theme.fontSmall
            width: parent.width
            wrapMode: Text.WordWrap
          }
          GameButton {
            theme: home.theme
            variant: "primary"
            text: "REPRENDRE LA PARTIE"
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
          text: "NOUVELLE PARTIE"
          icon: "plus"
          onClicked: home.newGameRequested()
        }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: home.theme.space
          GameButton { theme: home.theme; variant: "ghost"; text: "Statistiques"; icon: "stats"; onClicked: home.statsRequested() }
          GameButton { theme: home.theme; variant: "ghost"; text: "Réglages"; icon: "settings"; onClicked: home.settingsRequested() }
        }
      }

      Column {
        width: parent.width
        spacing: 4
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: home.dictionary && home.dictionary.provider
            ? home.dictionary.provider.name() + "  ·  " + Format.formatInt(home.dictionary.provider.graph().wordCount) + " mots"
            : ""
          color: home.theme.muted
          font.family: home.theme.fontFamily
          font.pixelSize: home.theme.fontSmall
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: "Projet communautaire indépendant. SCRABBLE® est une marque de ses propriétaires respectifs ; ce jeu n’est ni affilié ni approuvé par eux."
          color: home.theme.alpha(home.theme.muted, 0.8)
          font.family: home.theme.fontFamily
          font.pixelSize: home.theme.fontCaption
        }
      }
    }
  }
}
