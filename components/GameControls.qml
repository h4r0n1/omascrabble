import QtQuick

// The turn actions under the rack:
//   ⟲  ⤨  (💡)        24 pts      [ÉCHANGER] [PASSER] [JOUER]
// plus "Contester le coup" when the rules allow it. The game screen drives
// keyboard focus here itself (`focusIndex`).
Item {
  id: controls

  property var theme
  property var controller
  property var shortcuts: ({})
  property bool compact: false
  property int focusIndex: -1          // keyboard focus, -1 = none
  property string scoreText: ""
  property bool scoreValid: false

  signal recallRequested()
  signal shuffleRequested()
  signal hintRequested()
  signal exchangeRequested()
  signal passRequested()
  signal playRequested()
  signal challengeRequested()

  readonly property var legal: controller ? controller.legal : ({})
  readonly property bool myTurn: controller ? controller.humanTurn : false
  readonly property bool practice: controller && controller.game ? controller.game.mode === "practice" : false
  readonly property bool hasPending: controller ? controller.pending.length > 0 : false

  // Ordered list used by keyboard navigation.
  readonly property var buttons: [recall, shuffle, hint, challenge, exchange, pass, play].filter(function(b) { return b.visible && b.enabled })
  function activate(index) { if (index >= 0 && index < buttons.length) buttons[index].clicked() }

  function label(name) {
    var s = shortcuts && shortcuts[name] ? shortcuts[name] : ""
    return s
  }

  implicitHeight: theme.controlHeight

  Row {
    id: left
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    GameButton {
      id: recall
      theme: controls.theme; icon: "recall"; variant: "ghost"; focusable: false
      enabled: controls.hasPending
      tooltip: "Rappeler les lettres"; shortcutHint: controls.label("cancel")
      keyboardFocus: controls.buttons[controls.focusIndex] === recall
      onClicked: controls.recallRequested()
    }
    GameButton {
      id: shuffle
      theme: controls.theme; icon: "shuffle"; variant: "ghost"; focusable: false
      enabled: controls.controller && controls.controller.isActive && controls.controller.game.players[controls.controller.viewer].kind === "human"
      tooltip: "Mélanger le chevalet"; shortcutHint: controls.label("shuffle")
      keyboardFocus: controls.buttons[controls.focusIndex] === shuffle
      onClicked: controls.shuffleRequested()
    }
    GameButton {
      id: hint
      visible: controls.practice
      theme: controls.theme; icon: "hint"; variant: "ghost"; focusable: false
      enabled: controls.myTurn
      tooltip: "Indice"; shortcutHint: controls.label("hint")
      keyboardFocus: controls.buttons[controls.focusIndex] === hint
      onClicked: controls.hintRequested()
    }
  }

  Text {
    id: score
    anchors.left: left.right
    anchors.leftMargin: controls.theme.spaceLarge
    anchors.right: right.left
    anchors.rightMargin: controls.theme.spaceLarge
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: controls.compact ? Text.AlignLeft : Text.AlignHCenter
    text: controls.scoreText
    elide: Text.ElideRight
    color: controls.scoreValid ? controls.theme.foreground : controls.theme.muted
    font.family: controls.theme.fontFamily
    font.pixelSize: controls.theme.fontTitle
    font.weight: Font.Bold
  }

  Row {
    id: right
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: controls.theme.space
    GameButton {
      id: challenge
      visible: !!controls.legal.challenge
      theme: controls.theme; variant: "secondary"; focusable: false
      text: controls.compact ? "Contester" : "Contester le coup"
      icon: "challenge"
      tooltip: "Faire vérifier les mots du dernier coup"; shortcutHint: controls.label("challenge")
      keyboardFocus: controls.buttons[controls.focusIndex] === challenge
      onClicked: controls.challengeRequested()
    }
    GameButton {
      id: exchange
      theme: controls.theme; variant: "secondary"; focusable: false
      text: controls.compact ? "" : "ÉCHANGER"; icon: controls.compact ? "exchange" : ""
      enabled: !!controls.legal.exchange
      tooltip: controls.compact ? "Échanger" : (controls.legal.exchange ? "" : "Moins de 7 lettres dans le sac")
      shortcutHint: controls.label("exchange")
      keyboardFocus: controls.buttons[controls.focusIndex] === exchange
      onClicked: controls.exchangeRequested()
    }
    GameButton {
      id: pass
      theme: controls.theme; variant: "secondary"; focusable: false
      text: controls.compact ? "" : "PASSER"; icon: controls.compact ? "pass" : ""
      enabled: !!controls.legal.pass
      tooltip: controls.compact ? "Passer" : ""; shortcutHint: controls.label("pass")
      keyboardFocus: controls.buttons[controls.focusIndex] === pass
      onClicked: controls.passRequested()
    }
    GameButton {
      id: play
      theme: controls.theme; variant: "primary"; focusable: false
      text: "JOUER"
      enabled: controls.myTurn && controls.hasPending && (!controls.controller.preview || controls.controller.preview.valid || controls.controller.preview.reason === "DICTIONARY_UNAVAILABLE")
      shortcutHint: controls.label("confirm")
      keyboardFocus: controls.buttons[controls.focusIndex] === play
      onClicked: controls.playRequested()
    }
  }
}
