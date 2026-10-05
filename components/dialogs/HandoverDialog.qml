import QtQuick
import ".."

// Local two-player games: the rack stays hidden until the next player is at
// the keyboard.
Dialog {
  id: dlg

  property string playerName: ""
  property string lastMoveText: ""

  signal reveal()

  title: theme.t("handover.title", { name: playerName })
  message: (lastMoveText !== "" ? lastMoveText + "\n\n" : "") + theme.t("handover.message")
  dismissible: false
  preferredWidth: 400
  Keys.onReturnPressed: reveal()
  Keys.onEnterPressed: reveal()
  Keys.onSpacePressed: reveal()

  Row {
    anchors.right: parent.right
    GameButton { theme: dlg.theme; text: dlg.theme.t("handover.button"); variant: "primary"; onClicked: dlg.reveal() }
  }
}
