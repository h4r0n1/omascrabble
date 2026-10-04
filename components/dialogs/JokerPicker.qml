import QtQuick
import ".."

// Which letter does the joker stand for? Click a letter or type it.
Dialog {
  id: picker

  property int chosenIndex: 0
  signal chosen(string letter)
  signal cancelled()

  title: "Lettre du joker"
  message: "Le joker vaut 0 point et garde sa couleur sur le plateau. Tapez une lettre ou cliquez-la."
  preferredWidth: 420
  onDismissed: cancelled()
  onOpenChanged: if (open) chosenIndex = 4

  Keys.onPressed: function(event) {
    var t = String(event.text || "").toUpperCase()
    if (/^[A-Z]$/.test(t)) { picker.chosen(t); event.accepted = true; return }
    if (event.key === Qt.Key_Left) { chosenIndex = Math.max(0, chosenIndex - 1); event.accepted = true }
    else if (event.key === Qt.Key_Right) { chosenIndex = Math.min(25, chosenIndex + 1); event.accepted = true }
    else if (event.key === Qt.Key_Up) { chosenIndex = Math.max(0, chosenIndex - 7); event.accepted = true }
    else if (event.key === Qt.Key_Down) { chosenIndex = Math.min(25, chosenIndex + 7); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      picker.chosen(String.fromCharCode(65 + chosenIndex)); event.accepted = true
    }
  }

  Grid {
    id: grid
    columns: 7
    spacing: Math.round(cellSize * 0.18)
    anchors.horizontalCenter: parent.horizontalCenter
    readonly property real cellSize: Math.floor((picker.width > 0 ? Math.min(picker.preferredWidth, picker.width) - 2 * picker.theme.padding - 6 * 8 : 300) / 7.4)
    Repeater {
      model: 26
      Item {
        required property int index
        width: grid.cellSize
        height: grid.cellSize
        Tile {
          theme: picker.theme
          size: grid.cellSize
          letter: String.fromCharCode(65 + index)
          joker: true
          focused: picker.chosenIndex === index
          scale: mouse.containsMouse ? 1.06 : 1
          Behavior on scale { NumberAnimation { duration: picker.theme.anim(90) } }
        }
        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: picker.chosen(String.fromCharCode(65 + index))
        }
      }
    }
  }

  Row {
    anchors.right: parent.right
    GameButton { theme: picker.theme; text: "Annuler"; variant: "ghost"; onClicked: picker.cancelled() }
  }
}
