import QtQuick
import ".."

// The result of a challenge: every word that was checked, how it is spelled
// in French, whether it is valid, and what happens next.
Dialog {
  id: dlg

  property var outcome: null           // controller.challengeOutcome
  property var forms: ({})             // word → accented spellings
  property string dictionaryName: ""

  signal closed()

  property int viewer: 0
  readonly property bool youChallenged: !!outcome && outcome.challenger === viewer
  property var controller: null
  readonly property bool computerChallenged: !!outcome && !!controller && !!controller.game && controller.game.players[outcome.challenger].kind === "ai" && controller.game.mode !== "ai_vs_ai"

  title: !outcome ? ""
    : theme.t(computerChallenged ? (outcome.success ? "challenge.byComputer.success" : "challenge.byComputer.failure")
                                 : (outcome.success ? "challenge.success" : "challenge.failure"))
  message: !outcome ? ""
    : theme.t((computerChallenged ? "challenge.byComputer." : "challenge.") + (outcome.success ? "success" : "failure") + ".message")
      + (outcome.success ? "" : penaltyText())
  preferredWidth: 460
  onDismissed: closed()
  Keys.onReturnPressed: closed()
  Keys.onEnterPressed: closed()

  function penaltyText() {
    if (!outcome || !outcome.penalty) return ""
    var args = { you: youChallenged && !computerChallenged, n: outcome.penalty.points,
                 who: computerChallenged ? theme.t("player.computerSubject") : (controller ? controller.playerLabel(outcome.challenger) : "") }
    if (outcome.penalty.type === "points") return theme.t("challenge.penalty.points", args)
    if (outcome.penalty.type === "lose_turn") return theme.t("challenge.penalty.loseTurn", args)
    return ""
  }


  Text {
    width: parent.width
    text: dlg.theme.t("challenge.checked", { dictionary: dlg.dictionaryName })
    color: dlg.theme.muted
    font.family: dlg.theme.fontFamily
    font.pixelSize: dlg.theme.fontSmall
    font.weight: Font.Bold
    font.letterSpacing: 0.8
  }

  Column {
    width: parent.width
    spacing: 6
    Repeater {
      model: dlg.outcome ? dlg.outcome.checked : []
      Rectangle {
        required property var modelData
        width: parent.width
        height: wordRow.implicitHeight + 14
        radius: dlg.theme.radius
        color: modelData.valid ? dlg.theme.panel : dlg.theme.alpha(dlg.theme.urgent, 0.12)
        border.width: dlg.theme.borderWidth
        border.color: modelData.valid ? dlg.theme.line : dlg.theme.alpha(dlg.theme.urgent, 0.6)
        Row {
          id: wordRow
          anchors.verticalCenter: parent.verticalCenter
          x: 12
          spacing: 12
          Icon {
            name: modelData.valid ? "check" : "close"
            color: modelData.valid ? dlg.theme.accent : dlg.theme.urgent
            width: 18; height: 18
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: modelData.word
            color: dlg.theme.foreground
            font.family: dlg.theme.fontFamily
            font.pixelSize: dlg.theme.fontTitle
            font.weight: Font.Bold
            font.letterSpacing: 1
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            readonly property var spellings: dlg.forms[modelData.word] || []
            text: modelData.valid ? (spellings.length ? spellings.join(", ") : "") : dlg.theme.t("challenge.notInDictionary")
            color: dlg.theme.muted
            font.family: dlg.theme.fontFamily
            font.pixelSize: dlg.theme.fontBody
            font.italic: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }

  Row {
    anchors.right: parent.right
    GameButton { theme: dlg.theme; text: dlg.theme.t("common.continue"); variant: "primary"; onClicked: dlg.closed() }
  }
}
