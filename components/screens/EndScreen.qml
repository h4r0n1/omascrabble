import QtQuick
import QtQuick.Controls
import ".."
import "../../engine/stats.mjs" as Stats

// Partie terminée: who won and why, how the final scores were adjusted, the
// game's statistics and every word played.
FocusScope {
  id: end

  property var theme
  property var controller

  signal newGameRequested()
  signal replayRequested()
  signal rematchRequested()
  signal closeRequested()
  signal wordRequested(int moveIndex)

  readonly property var g: controller ? controller.game : null
  readonly property var info: g && g.end ? g.end : null
  readonly property int me: controller ? controller.viewerIndex(g) : 0
  readonly property var summary: g && info ? Stats.summarizeGame(g, me) : null

  onVisibleChanged: if (visible) Qt.callLater(function() { end.forceActiveFocus() })
  Keys.onEscapePressed: closeRequested()

  function tr(key, args) { return theme.t(key, args) }
  function name(index) { return controller ? controller.playerLabel(index) : "" }

  function title() {
    if (!info) return ""
    if (g.players.length === 1) return tr("end.gameOver")
    if (info.winner === null) return tr("end.draw")
    if (g.mode === "human_vs_ai") return tr(info.winner === me ? "end.victory" : "end.defeat")
    if (g.mode === "ai_vs_ai") return tr("end.winsDemo", { name: name(info.winner) })
    return tr("end.winsNamed", { name: name(info.winner) })
  }

  // Default labels ("Vous", "Ordinateur") need real sentences.
  function isYou(index) { return g && g.mode !== "human_vs_human" && g.players[index] && g.players[index].kind === "human" }
  function isComputer(index) { return g && g.players[index] && g.players[index].kind === "ai" }

  function reason() {
    if (!info) return ""
    var a = info.actor
    var known = a !== null && a !== undefined && !!g.players[a]
    var who = !known ? "" : isComputer(a) && g.mode !== "ai_vs_ai" ? tr("player.computerSubject") : name(a)
    if (info.reason === "out") return known && isYou(a) ? tr("end.reason.out.you") : tr("end.reason.out", { who: who })
    if (info.reason === "scoreless") return tr("end.reason.scoreless")
    if (info.reason === "timeout") return known && isYou(a) ? tr("end.reason.timeout.you")
      : tr("end.reason.timeout", { who: isComputer(a) && g.mode !== "ai_vs_ai" ? tr("end.computerLower") : who })
    if (info.reason === "resign") return known && isYou(a) ? tr("end.reason.resign.you") : tr("end.reason.resign", { who: who })
    return ""
  }

  function wordsTitle(index) {
    if (isYou(index)) return tr("end.wordsYou")
    if (isComputer(index) && g.mode !== "ai_vs_ai") return tr("end.wordsComputer")
    return tr("end.wordsNamed", { name: name(index) })
  }

  function duration(ms) {
    var m = Math.round(ms / 60000)
    return m < 1 ? tr("common.lessThanAMinute") : tr("common.minutes", { n: m })
  }

  function wordsOf(player) {
    if (!g) return []
    return g.moves.filter(function(m) { return m.player === player && m.type === "play" && !m.withdrawn })
      .map(function(m) { return { text: m.words[0].notation || m.words[0].word, score: m.score, bingo: m.bingo, position: m.position, index: m.index } })
  }

  Rectangle {
    anchors.fill: parent
    color: end.theme.scrim
    MouseArea { anchors.fill: parent }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(720, parent.width - 2 * end.theme.spaceHuge)
    height: Math.min(parent.height - 2 * end.theme.spaceHuge, content.implicitHeight + 2 * end.theme.padding + buttons.height + end.theme.spaceLarge)
    radius: end.theme.radius
    color: end.theme.background
    border.width: end.theme.borderWidth
    border.color: end.theme.lineStrong

    Flickable {
      anchors.fill: parent
      anchors.margins: end.theme.padding
      anchors.bottomMargin: buttons.height + end.theme.padding + end.theme.spaceLarge
      contentHeight: content.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: content
        width: parent.width
        spacing: end.theme.spaceLarge

        Row {
          spacing: end.theme.spaceLarge
          Icon {
            name: "trophy"
            color: end.info && end.info.winner === end.me ? end.theme.accent : end.theme.muted
            width: 34; height: 34
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              text: end.title()
              color: end.theme.foreground
              font.family: end.theme.fontFamily
              font.pixelSize: end.theme.fontDisplayLarge
              font.weight: Font.Bold
            }
            Text {
              textFormat: Text.PlainText
              text: end.reason()
              color: end.theme.muted
              font.family: end.theme.fontFamily
              font.pixelSize: end.theme.fontBody
              width: content.width - 60
              wrapMode: Text.WordWrap
            }
          }
        }

        // Final scores with the end-of-game adjustments.
        Column {
          width: parent.width
          spacing: 2
          Repeater {
            model: end.g ? end.g.players.length : 0
            Rectangle {
              required property int index
              width: content.width
              height: end.theme.fontHeading * 2.4
              radius: end.theme.radius
              color: end.info && end.info.winner === index ? end.theme.alpha(end.theme.accent, 0.1) : end.theme.panel
              border.width: end.theme.borderWidth
              border.color: end.info && end.info.winner === index ? end.theme.alpha(end.theme.accent, 0.5) : end.theme.line
              Text {
                textFormat: Text.PlainText
                x: end.theme.padding
                anchors.verticalCenter: parent.verticalCenter
                text: end.name(index)
                color: end.theme.foreground
                font.family: end.theme.fontFamily
                font.pixelSize: end.theme.fontTitle
                font.weight: Font.Bold
              }
              Text {
                textFormat: Text.PlainText
                anchors.right: final.left
                anchors.rightMargin: end.theme.spaceHuge
                anchors.verticalCenter: parent.verticalCenter
                readonly property int adj: end.info ? end.info.adjustments[index] : 0
                text: end.g.players[index].score + (adj !== 0 ? (adj > 0 ? "  + " + adj : "  − " + (-adj)) + (end.info.timePenalties && end.info.timePenalties[index] ? end.tr("end.adjustTime") : end.tr("end.adjustTiles")) : "")
                color: end.theme.muted
                font.family: end.theme.fontFamily
                font.pixelSize: end.theme.fontSmall
              }
              Text {
                textFormat: Text.PlainText
                id: final
                anchors.right: parent.right
                anchors.rightMargin: end.theme.padding
                anchors.verticalCenter: parent.verticalCenter
                text: end.info ? end.info.finalScores[index] : ""
                color: end.theme.foreground
                font.family: end.theme.fontFamily
                font.pixelSize: end.theme.fontDisplay
                font.weight: Font.Bold
              }
            }
          }
        }

        // This game, in numbers.
        Flow {
          width: parent.width
          spacing: end.theme.space
          Repeater {
            model: end.summary ? [
              [end.tr("end.stat.moves"), end.summary.moveScores.length],
              [end.tr("end.stat.average"), end.summary.moveScores.length ? Math.round(end.summary.moveScores.reduce(function(a, b) { return a + b }, 0) / end.summary.moveScores.length) : 0],
              [end.tr("end.stat.scrabbles"), end.summary.scrabbles],
              [end.tr("end.stat.best"), end.summary.bestWord ? end.summary.bestWord.notation + " · " + end.summary.bestWord.score : "—"],
              [end.tr("end.stat.tiles"), end.summary.tilesPlayed],
              [end.tr("end.stat.duration"), end.duration(end.summary.durationMs)]
            ] : []
            Rectangle {
              required property var modelData
              width: (content.width - 2 * end.theme.space) / 3
              height: statColumn.implicitHeight + 2 * end.theme.space
              radius: end.theme.radius
              color: end.theme.panel
              Column {
                id: statColumn
                x: end.theme.space + 2
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 2 * end.theme.space
                Text {
                  textFormat: Text.PlainText
                  text: modelData[0].toUpperCase()
                  color: end.theme.muted
                  font.family: end.theme.fontFamily
                  font.pixelSize: end.theme.fontCaption
                  font.weight: Font.Bold
                  font.letterSpacing: 1
                }
                Text {
                  textFormat: Text.PlainText
                  text: String(modelData[1])
                  width: parent.width
                  elide: Text.ElideRight
                  color: end.theme.foreground
                  font.family: end.theme.fontFamily
                  font.pixelSize: end.theme.fontTitle
                  font.weight: Font.Bold
                }
              }
            }
          }
        }

        // Every word played.
        Row {
          width: parent.width
          spacing: end.theme.spaceLarge
          Repeater {
            model: end.g ? end.g.players.length : 0
            Column {
              required property int index
              width: (content.width - (end.g.players.length - 1) * end.theme.spaceLarge) / end.g.players.length
              spacing: 2
              Text {
                textFormat: Text.PlainText
                text: end.wordsTitle(index)
                color: end.theme.muted
                font.family: end.theme.fontFamily
                font.pixelSize: end.theme.fontCaption
                font.weight: Font.Bold
                font.letterSpacing: 1
              }
              Repeater {
                model: end.wordsOf(index)
                Item {
                  required property var modelData
                  width: parent.width
                  height: end.theme.fontBody * 1.7
                  Text {
                    textFormat: Text.PlainText
                    text: modelData.text
                    color: modelData.bingo ? end.theme.accent : end.theme.foreground
                    font.family: end.theme.fontFamily
                    font.pixelSize: end.theme.fontBody
                    font.letterSpacing: 0.6
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: end.wordRequested(modelData.index)
                  }
                  Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.score
                    color: end.theme.muted
                    font.family: end.theme.fontFamily
                    font.pixelSize: end.theme.fontBody
                  }
                }
              }
            }
          }
        }
      }
    }

    Row {
      id: buttons
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: end.theme.padding
      spacing: end.theme.space
      GameButton { theme: end.theme; text: end.tr("common.close"); variant: "ghost"; onClicked: end.closeRequested() }
      GameButton { theme: end.theme; text: end.tr("end.replay"); icon: "replay"; variant: "secondary"; onClicked: end.replayRequested() }
      GameButton { theme: end.theme; text: end.tr("end.rematch"); variant: "secondary"; visible: !!end.g && end.g.mode !== "practice" && end.g.mode !== "ai_vs_ai"; onClicked: end.rematchRequested() }
      GameButton { theme: end.theme; text: end.tr("end.newGame"); variant: "primary"; onClicked: end.newGameRequested() }
    }
  }
}
