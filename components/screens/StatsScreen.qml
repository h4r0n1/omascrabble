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
    return m < 1 ? "—" : (m >= 60 ? tr("common.hoursMinutes", { h: Math.floor(m / 60), m: m % 60 }) : tr("common.minutes", { n: m }))
  }
  function n(v) { return Format.formatInt(v) }
  function tr(key, args) { return theme.t(key, args) }

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
        GameButton { theme: stats.theme; icon: "back"; variant: "ghost"; focusable: false; tooltip: stats.tr("common.back"); onClicked: stats.closed(); anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: stats.tr("stats.title")
          color: stats.theme.foreground
          font.family: stats.theme.fontFamily
          font.pixelSize: stats.theme.fontDisplay
          font.weight: Font.Bold
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        visible: stats.s.gamesPlayed === 0
        text: stats.tr("stats.empty")
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
            [stats.tr("stats.games"), stats.n(stats.s.gamesPlayed), ""],
            [stats.tr("stats.wins"), stats.n(stats.s.wins), stats.s.wins + stats.s.losses + stats.s.draws > 0 ? stats.tr("stats.winRate", { n: Math.round(stats.d.winRate * 100) }) : ""],
            [stats.tr("stats.losses"), stats.n(stats.s.losses), ""],
            [stats.tr("stats.draws"), stats.n(stats.s.draws), ""]
          ]
          StatTile { required property var modelData; theme: stats.theme; width: (headline.width - (headline.columns - 1) * headline.spacing) / headline.columns; label: modelData[0]; value: modelData[1]; detail: modelData[2] }
        }
      }

      SectionTitle { width: parent.width; theme: stats.theme; text: stats.tr("stats.records") }
      Grid {
        id: records
        columns: width > 620 ? 3 : 2
        width: parent.width
        spacing: stats.theme.space
        Repeater {
          model: [
            [stats.tr("stats.bestScore"), stats.s.highestScore ? stats.n(stats.s.highestScore.score) : "—", ""],
            [stats.tr("stats.bestMove"), stats.s.highestWord ? stats.s.highestWord.notation : "—", stats.s.highestWord ? stats.tr("common.points", { n: stats.s.highestWord.score }) : ""],
            [stats.tr("stats.scrabbles"), stats.n(stats.s.scrabbles), stats.tr("stats.scrabbles.detail")],
            [stats.tr("stats.bestDifficulty"), stats.s.bestDifficultyDefeated ? stats.tr("difficulty." + stats.s.bestDifficultyDefeated) : "—", ""],
            [stats.tr("stats.averageScore"), stats.n(stats.d.averageScore), stats.tr("stats.perGame")],
            [stats.tr("stats.pointsPerMove"), stats.theme.language === "en" ? String(Math.round(stats.d.averageMoveScore * 10) / 10) : Format.formatDecimal(stats.d.averageMoveScore, 1), stats.tr("stats.onAverage")]
          ]
          StatTile { required property var modelData; theme: stats.theme; width: (records.width - (records.columns - 1) * records.spacing) / records.columns; label: modelData[0]; value: modelData[1]; detail: modelData[2] }
        }
      }

      SectionTitle { width: parent.width; theme: stats.theme; text: stats.tr("stats.habits") }
      Grid {
        id: habits
        columns: width > 620 ? 5 : 3
        width: parent.width
        spacing: stats.theme.space
        Repeater {
          model: [
            [stats.tr("stats.averageDuration"), stats.fmtDuration(stats.d.averageDurationMs)],
            [stats.tr("stats.tilesPlayed"), stats.n(stats.s.tilesPlayed)],
            [stats.tr("stats.exchanges"), stats.n(stats.s.exchanges)],
            [stats.tr("stats.passes"), stats.n(stats.s.passes)],
            [stats.tr("stats.challenges"), stats.n(stats.s.challenges)]
          ]
          StatTile { required property var modelData; theme: stats.theme; compact: true; width: (habits.width - (habits.columns - 1) * habits.spacing) / habits.columns; label: modelData[0]; value: modelData[1] }
        }
      }

      SectionTitle { visible: stats.s.recent.length > 0; width: parent.width; theme: stats.theme; text: stats.tr("stats.recent") }
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
              text: stats.tr("stats.result." + modelData.result)
                + (modelData.difficulty ? " · " + stats.tr("difficulty." + modelData.difficulty) : modelData.mode === "human_vs_human" ? " · " + stats.tr("stats.twoPlayers") : "")
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
                + "   ·   " + new Date(modelData.date).toLocaleDateString(Qt.locale(stats.theme.language === "en" ? "en_GB" : "fr_FR"), "d MMM yyyy")
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
