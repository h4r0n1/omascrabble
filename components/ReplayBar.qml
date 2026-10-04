import QtQuick

// Step through a game move by move. The board shows the position after the
// selected move, with that move highlighted.
Rectangle {
  id: bar

  property var theme
  property var controller
  property bool active: false

  signal closed()

  readonly property int moveCount: controller && controller.game ? controller.game.moves.length : 0
  property int index: moveCount - 1

  onActiveChanged: {
    if (!controller) return
    if (active) { index = moveCount - 1; controller.replayIndex = index }
    else controller.replayIndex = -1
    controller.revision++
  }
  onIndexChanged: if (active && controller) { controller.replayIndex = index; controller.revision++ }

  focus: active
  Keys.onLeftPressed: index = Math.max(0, index - 1)
  Keys.onRightPressed: index = Math.min(moveCount - 1, index + 1)
  Keys.onEscapePressed: closed()

  width: row.implicitWidth + 2 * theme.padding
  height: theme.controlHeight + theme.padding
  radius: theme.radius
  color: theme.panelStrong
  border.width: theme.borderWidth
  border.color: theme.lineStrong

  readonly property var move: controller && controller.game && index >= 0 ? controller.game.moves[index] : null

  Row {
    id: row
    anchors.centerIn: parent
    spacing: bar.theme.space
    GameButton { theme: bar.theme; icon: "first"; variant: "ghost"; focusable: false; onClicked: bar.index = 0 }
    GameButton { theme: bar.theme; icon: "prev"; variant: "ghost"; focusable: false; onClicked: bar.index = Math.max(0, bar.index - 1) }
    Text {
      width: 220
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: !bar.move ? "" : "Coup " + (bar.index + 1) + " / " + bar.moveCount + "  ·  "
        + (bar.move.type === "play" ? (bar.move.words[0].notation || bar.move.words[0].word) + " " + bar.move.score : bar.move.type === "pass" ? "passe" : bar.move.type === "exchange" ? "échange" : bar.move.type)
      color: bar.theme.foreground
      font.family: bar.theme.fontFamily
      font.pixelSize: bar.theme.fontBody
    }
    GameButton { theme: bar.theme; icon: "next"; variant: "ghost"; focusable: false; onClicked: bar.index = Math.min(bar.moveCount - 1, bar.index + 1) }
    GameButton { theme: bar.theme; icon: "last"; variant: "ghost"; focusable: false; onClicked: bar.index = bar.moveCount - 1 }
    GameButton { theme: bar.theme; icon: "close"; variant: "ghost"; focusable: false; tooltip: "Quitter la relecture"; onClicked: bar.closed() }
  }
}
