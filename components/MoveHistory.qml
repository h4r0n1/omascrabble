import QtQuick
import QtQuick.Controls

// The game so far, in French notation:
//   1. MONTAG(E)   H4    28
// A joker is in parentheses; H4 is horizontal from row H, column 4, and 4H
// vertical. Clicking a move highlights its tiles on the board.
Item {
  id: history

  property var theme
  property var controller
  property var entries: controller ? controller.moveList : []
  property int highlighted: controller ? controller.highlightMove : -1

  signal moveActivated(int index)

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    model: history.entries
    spacing: 0
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    onCountChanged: Qt.callLater(function() { list.positionViewAtEnd() })

    delegate: Rectangle {
      required property var modelData
      required property int index
      width: list.width
      height: Math.round(history.theme.fontBody * 2.1)
      color: history.highlighted === modelData.index ? history.theme.alpha(history.theme.accent, 0.14)
        : rowMouse.containsMouse ? history.theme.alpha(history.theme.foreground, 0.05) : "transparent"
      radius: history.theme.radius

      Rectangle {
        id: dot
        width: 7; height: 7; radius: 3.5
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        color: modelData.player === 0 ? history.theme.accent : history.theme.muted
      }
      Text {
        textFormat: Text.PlainText
        id: num
        anchors.left: dot.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(history.theme.fontBody * 2.2)
        text: modelData.number > 0 ? modelData.number + "." : ""
        color: history.theme.muted
        font.family: history.theme.fontFamily
        font.pixelSize: history.theme.fontSmall
      }
      Text {
        textFormat: Text.PlainText
        anchors.left: num.right
        anchors.right: pos.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.text
        elide: Text.ElideRight
        color: modelData.withdrawn ? history.theme.muted : modelData.type === "play" ? history.theme.foreground : history.theme.muted
        font.family: history.theme.fontFamily
        font.pixelSize: history.theme.fontBody
        font.weight: modelData.type === "play" ? Font.DemiBold : Font.Normal
        font.strikeout: modelData.withdrawn
        font.italic: modelData.type !== "play"
        font.letterSpacing: modelData.type === "play" ? 0.6 : 0
      }
      Text {
        textFormat: Text.PlainText
        id: pos
        anchors.right: score.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.position || ""
        color: history.theme.muted
        font.family: history.theme.fontFamily
        font.pixelSize: history.theme.fontSmall
      }
      Text {
        textFormat: Text.PlainText
        id: score
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(history.theme.fontBody * 2.6)
        horizontalAlignment: Text.AlignRight
        text: modelData.type === "play" || modelData.score !== 0 ? modelData.score : "—"
        color: modelData.bingo ? history.theme.accent : history.theme.foreground
        font.family: history.theme.fontFamily
        font.pixelSize: history.theme.fontBody
        font.weight: modelData.bingo ? Font.Bold : Font.Normal
        font.features: { "tnum": 1 }
      }
      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: modelData.type === "play" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: history.moveActivated(modelData.index)
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: list.count === 0
      anchors.centerIn: parent
      text: history.theme.t("history.empty")
      color: history.theme.muted
      font.family: history.theme.fontFamily
      font.pixelSize: history.theme.fontSmall
    }
  }
}
