import QtQuick
import ".."

// Local two-player games: the rack stays hidden until the next player is at
// the keyboard.
Dialog {
  id: dlg

  property string playerName: ""
  property string lastMoveText: ""

  signal reveal()

  title: "Au tour de " + playerName
  message: (lastMoveText !== "" ? lastMoveText + "\n\n" : "") + "Passez le clavier, puis affichez votre chevalet."
  dismissible: false
  preferredWidth: 400
  Keys.onReturnPressed: reveal()
  Keys.onEnterPressed: reveal()
  Keys.onSpacePressed: reveal()

  Row {
    anchors.right: parent.right
    GameButton { theme: dlg.theme; text: "Afficher mon chevalet"; variant: "primary"; onClicked: dlg.reveal() }
  }
}
