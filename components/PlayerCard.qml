import QtQuick

// One player's score card: name, score (counting up when it changes), whose
// turn it is, the clock, and a "+42" that rises when a move scores.
Rectangle {
  id: card

  property var theme
  property string name: ""
  property string subtitle: ""
  property int score: 0
  property bool active: false
  property bool thinking: false
  property string status: ""
  property bool showClock: false
  property real remainingMs: 0
  property int rackCount: 7
  property bool compact: false
  property bool alignRight: false

  signal scored(int points, bool bingo)

  radius: theme.radius
  color: active ? theme.alpha(theme.accent, theme.dark ? 0.08 : 0.07) : theme.panel
  border.width: theme.borderWidth
  border.color: active ? theme.alpha(theme.accent, 0.55) : theme.line
  implicitHeight: column.implicitHeight + theme.padding * (compact ? 0.9 : 1.2)
  Behavior on color { ColorAnimation { duration: card.theme.anim(220) } }
  Behavior on border.color { ColorAnimation { duration: card.theme.anim(220) } }

  // Shown score animates towards the real one.
  property real shownScore: score
  Behavior on shownScore { enabled: card.theme.motionEnabled; NumberAnimation { duration: card.theme.anim(520); easing.type: Easing.OutCubic } }

  function formatClock(ms) {
    var total = Math.max(0, Math.ceil(ms / 1000))
    var m = Math.floor(total / 60)
    var s = total % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  onScored: function(points, bingo) {
    flyout.text = (points >= 0 ? "+" : "") + points + (bingo ? "  Scrabble !" : "")
    if (!theme.motionEnabled) return
    flyout.y = flyoutBase
    flyout.opacity = 0
    flyAnim.restart()
  }
  readonly property real flyoutBase: column.y + scoreText.parent.y + (scoreText.implicitHeight - flyout.implicitHeight) / 2

  // Accent bar on the active card
  Rectangle {
    visible: card.active
    width: Math.max(3, card.theme.borderWidth * 3)
    height: parent.height - 2 * card.theme.borderWidth
    x: card.alignRight ? parent.width - width - card.theme.borderWidth : card.theme.borderWidth
    y: card.theme.borderWidth
    color: card.theme.accent
    radius: card.theme.radius > 0 ? width / 2 : 0
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: card.theme.padding
    anchors.rightMargin: card.theme.padding
    spacing: card.compact ? 2 : card.theme.spaceSmall

    Item {
      width: parent.width
      height: nameRow.implicitHeight
      Row {
      id: nameRow
      anchors.right: card.alignRight ? parent.right : undefined
      spacing: card.theme.space
      Text {
        text: card.name.toUpperCase()
        color: card.active ? card.theme.foreground : card.theme.muted
        font.family: card.theme.fontFamily
        font.pixelSize: card.theme.fontSmall
        font.weight: Font.Bold
        font.letterSpacing: 1.2
        elide: Text.ElideRight
        width: Math.min(implicitWidth, card.width * 0.55)
      }
      Text {
        visible: card.subtitle !== ""
        text: card.subtitle
        color: card.theme.muted
        font.family: card.theme.fontFamily
        font.pixelSize: card.theme.fontCaption
        anchors.verticalCenter: parent.verticalCenter
      }
      }
    }

    Item {
      width: parent.width
      height: scoreText.implicitHeight
      Text {
        id: scoreText
        anchors.left: card.alignRight ? undefined : parent.left
        anchors.right: card.alignRight ? parent.right : undefined
        text: Math.round(card.shownScore)
        color: card.theme.foreground
        font.family: card.theme.fontFamily
        font.pixelSize: card.compact ? card.theme.fontDisplay : card.theme.fontDisplayLarge
        font.weight: Font.Bold
      }
      Text {
        visible: card.showClock
        anchors.right: card.alignRight ? undefined : parent.right
        anchors.left: card.alignRight ? parent.left : undefined
        anchors.verticalCenter: scoreText.verticalCenter
        text: card.formatClock(card.remainingMs)
        color: card.remainingMs < 60000 && card.active ? card.theme.urgent : card.active ? card.theme.foreground : card.theme.muted
        font.family: card.theme.fontFamily
        font.pixelSize: card.theme.fontTitle
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
      }
    }

    Item {
      width: parent.width
      height: Math.max(statusText.implicitHeight, dots.height)
      Row {
      anchors.right: card.alignRight ? parent.right : undefined
      height: parent.height
      spacing: card.theme.space
      Rectangle {
        visible: card.active && !card.thinking
        width: 7; height: 7; radius: 3.5
        color: card.theme.accent
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        id: statusText
        text: card.status
        color: card.active ? card.theme.foreground : card.theme.muted
        font.family: card.theme.fontFamily
        font.pixelSize: card.theme.fontSmall
        anchors.verticalCenter: parent.verticalCenter
      }
      ThinkingDots {
        id: dots
        visible: card.thinking
        theme: card.theme
        size: 5
        anchors.verticalCenter: parent.verticalCenter
      }
      }
    }
  }

  // Rises beside the score, inside the card.
  Text {
    id: flyout
    x: column.x + (card.alignRight ? column.width - scoreText.implicitWidth - width - 12 : scoreText.implicitWidth + 12)
    y: card.flyoutBase
    opacity: 0
    color: card.theme.accent
    font.family: card.theme.fontFamily
    font.pixelSize: card.theme.fontHeading
    font.weight: Font.Bold
    SequentialAnimation {
      id: flyAnim
      ParallelAnimation {
        NumberAnimation { target: flyout; property: "opacity"; to: 1; duration: card.theme.anim(120) }
        NumberAnimation { target: flyout; property: "y"; to: card.flyoutBase - 10; duration: card.theme.anim(420); easing.type: Easing.OutCubic }
      }
      PauseAnimation { duration: card.theme.anim(500) }
      NumberAnimation { target: flyout; property: "opacity"; to: 0; duration: card.theme.anim(260) }
    }
  }

  Accessible.role: Accessible.StaticText
  Accessible.name: name + ", " + score + " points" + (active ? ", à son tour" : "")
}
