import QtQuick
import QtQuick.Controls
import ".."
import "../../app/format.mjs" as Format
import "../../engine/stats.mjs" as Stats
import "../../ai/difficulty.mjs" as Difficulty

// Statistiques: records, results and habits across games.
FocusScope {
  id: stats

  property var theme
  property var saves

  signal closed()

  readonly property var s: saves ? saves.stats : Stats.emptyStats()
  readonly property var d: Stats.deriveStats(s)

  onVisibleChanged: if (visible) Qt.callLater(function() { stats.forceActiveFocus() })
  Keys.onEscapePressed: closed()

  function fmtDuration(ms) {
    var m = Math.round(ms / 60000)
    return m < 1 ? "—" : (m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min")
  }
  function n(v) { return Format.formatInt(v) }

  Rectangle { anchors.fill: parent; color: stats.theme.background }

  Flickable {
    anchors.fill: parent
    contentHeight: body.implicitHeight + 2 * stats.theme.spaceHuge
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: body
      width: Math.min(820, parent.width - 2 * stats.theme.padding)
      x: (parent.width - width) / 2
      y: stats.theme.spaceHuge
      spacing: stats.theme.spaceHuge

      Row {
        spacing: stats.theme.space
        GameButton { theme: stats.theme; icon: "back"; variant: "ghost"; focusable: false; tooltip: "Retour"; onClicked: stats.closed(); anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: "Statistiques"
          color: stats.theme.foreground
          font.family: stats.theme.fontFamily
          font.pixelSize: stats.theme.fontDisplay
          font.weight: Font.Bold
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        visible: stats.s.gamesPlayed === 0
        text: "Aucune partie terminée pour l’instant. Vos statistiques apparaîtront ici."
        color: stats.theme.muted
        font.family: stats.theme.fontFamily
        font.pixelSize: stats.theme.fontBody
      }

      // Headline numbers.
      Grid {
        id: headline
        columns: width > 620 ? 4 : 2
        width: parent.width
        spacing: stats.theme.space
        Repeater {
          model: [
            ["Parties", stats.n(stats.s.gamesPlayed), ""],
            ["Victoires", stats.n(stats.s.wins), stats.s.wins + stats.s.losses + stats.s.draws > 0 ? Math.round(stats.d.winRate * 100) + " % contre l’ordinateur" : ""],
            ["Défaites", stats.n(stats.s.losses), ""],
            ["Égalités", stats.n(stats.s.draws), ""]
          ]
          StatTile { required property var modelData; theme: stats.theme; width: (headline.width - (headline.columns - 1) * headline.spacing) / headline.columns; label: modelData[0]; value: modelData[1]; detail: modelData[2] }
        }
      }

      SectionTitle { width: parent.width; theme: stats.theme; text: "Records" }
      Grid {
        id: records
        columns: width > 620 ? 3 : 2
        width: parent.width
        spacing: stats.theme.space
        Repeater {
          model: [
            ["Meilleur score", stats.s.highestScore ? stats.n(stats.s.highestScore.score) : "—", ""],
            ["Meilleur coup", stats.s.highestWord ? stats.s.highestWord.notation : "—", stats.s.highestWord ? stats.s.highestWord.score + " points" : ""],
            ["Scrabbles", stats.n(stats.s.scrabbles), "7 lettres posées d’un coup"],
            ["Meilleure difficulté battue", stats.s.bestDifficultyDefeated ? Difficulty.DIFFICULTY_LABELS[stats.s.bestDifficultyDefeated] : "—", ""],
            ["Score moyen", stats.n(stats.d.averageScore), "par partie"],
            ["Points par coup", Format.formatDecimal(stats.d.averageMoveScore, 1), "en moyenne"]
          ]
          StatTile { required property var modelData; theme: stats.theme; width: (records.width - (records.columns - 1) * records.spacing) / records.columns; label: modelData[0]; value: modelData[1]; detail: modelData[2] }
        }
      }

      SectionTitle { width: parent.width; theme: stats.theme; text: "Habitudes" }
      Grid {
        id: habits
        columns: width > 620 ? 5 : 3
        width: parent.width
        spacing: stats.theme.space
        Repeater {
          model: [
            ["Durée moyenne", stats.fmtDuration(stats.d.averageDurationMs)],
            ["Lettres posées", stats.n(stats.s.tilesPlayed)],
            ["Échanges", stats.n(stats.s.exchanges)],
            ["Passes", stats.n(stats.s.passes)],
            ["Contestations", stats.n(stats.s.challenges)]
          ]
          StatTile { required property var modelData; theme: stats.theme; compact: true; width: (habits.width - (habits.columns - 1) * habits.spacing) / habits.columns; label: modelData[0]; value: modelData[1] }
        }
      }

      SectionTitle { visible: stats.s.recent.length > 0; width: parent.width; theme: stats.theme; text: "Dernières parties" }
      Column {
        width: parent.width
        spacing: 2
        Repeater {
          model: stats.s.recent.slice(0, 12)
          Rectangle {
            required property var modelData
            width: body.width
            height: stats.theme.fontBody * 2.4
            radius: stats.theme.radius
            color: stats.theme.panel
            Text {
              x: stats.theme.padding
              anchors.verticalCenter: parent.verticalCenter
              text: (modelData.result === "win" ? "Victoire" : modelData.result === "loss" ? "Défaite" : modelData.result === "draw" ? "Égalité" : "Entraînement")
                + (modelData.difficulty ? " · " + (Difficulty.DIFFICULTY_LABELS[modelData.difficulty] || "") : modelData.mode === "human_vs_human" ? " · deux joueurs" : "")
              color: modelData.result === "win" ? stats.theme.accent : stats.theme.foreground
              font.family: stats.theme.fontFamily
              font.pixelSize: stats.theme.fontBody
              font.weight: Font.DemiBold
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: stats.theme.padding
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.score + (modelData.opponentScore !== null && modelData.opponentScore !== undefined ? " – " + modelData.opponentScore : "")
                + (modelData.bestWord ? "   ·   " + modelData.bestWord.notation + " " + modelData.bestWord.score : "")
                + "   ·   " + new Date(modelData.date).toLocaleDateString(Qt.locale("fr_FR"), "d MMM yyyy")
              color: stats.theme.muted
              font.family: stats.theme.fontFamily
              font.pixelSize: stats.theme.fontSmall
            }
          }
        }
      }
    }
  }
}
