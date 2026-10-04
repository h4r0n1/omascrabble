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
  readonly property bool computerChallenged: !!outcome && outcome.challengerName === "Ordinateur"

  title: !outcome ? ""
    : computerChallenged ? (outcome.success ? "L’ordinateur conteste votre coup" : "L’ordinateur conteste… à tort")
    : outcome.success ? "Contestation réussie" : "Contestation refusée"
  message: !outcome ? ""
    : computerChallenged
      ? (outcome.success ? "Votre coup est annulé : vos lettres reviennent sur votre chevalet et aucun point n’est marqué."
                         : "Tous vos mots sont valides : votre coup est maintenu." + penaltyText())
      : outcome.success ? "Le coup est annulé : ses lettres retournent sur le chevalet de son auteur et aucun point n’est marqué."
                        : "Tous les mots sont valides : le coup est maintenu." + penaltyText()
  preferredWidth: 460
  onDismissed: closed()
  Keys.onReturnPressed: closed()
  Keys.onEnterPressed: closed()

  function penaltyText() {
    if (!outcome || !outcome.penalty) return ""
    var who = computerChallenged ? "L’ordinateur" : youChallenged ? "Vous" : outcome.challengerName
    if (outcome.penalty.type === "points") return " " + who + (who === "Vous" ? " perdez " : " perd ") + outcome.penalty.points + " points."
    if (outcome.penalty.type === "lose_turn") return " " + who + (who === "Vous" ? " passez votre tour." : " passe son tour.")
    return ""
  }

  Text {
    width: parent.width
    text: "Mots vérifiés · " + dlg.dictionaryName
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
            text: modelData.valid ? (spellings.length ? spellings.join(", ") : "") : "absent du dictionnaire"
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
    GameButton { theme: dlg.theme; text: "Continuer"; variant: "primary"; onClicked: dlg.closed() }
  }
}
