import QtQuick
import ".."

// Pick the letters to put back in the bag.
Dialog {
  id: dlg

  property var tiles: []
  property int bagCount: 0
  property var selection: []
  property int cursor: 0

  signal confirmed(var tileIds)
  signal cancelled()

  title: theme.t("exchange.title")
  message: theme.t("exchange.message", { n: bagCount })
  preferredWidth: 520
  onDismissed: cancelled()
  onOpenChanged: if (open) { selection = []; cursor = 0 }

  function toggle(id) {
    var next = selection.slice()
    var i = next.indexOf(id)
    if (i === -1) next.push(id); else next.splice(i, 1)
    selection = next
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left) { cursor = Math.max(0, cursor - 1); event.accepted = true }
    else if (event.key === Qt.Key_Right) { cursor = Math.min(tiles.length - 1, cursor + 1); event.accepted = true }
    else if (event.key === Qt.Key_Space) { if (tiles[cursor]) toggle(tiles[cursor].id); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (selection.length) confirmed(selection); event.accepted = true }
    else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) { selection = tiles.map(function(t) { return t.id }); event.accepted = true }
  }

  Row {
    id: row
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Math.round(size * 0.16)
    readonly property real size: Math.min(56, Math.floor((Math.min(dlg.preferredWidth, dlg.width) - 2 * dlg.theme.padding) / 8))
    Repeater {
      model: dlg.tiles
      Item {
        required property var modelData
        required property int index
        width: row.size
        height: row.size * 1.25
        readonly property bool picked: dlg.selection.indexOf(modelData.id) !== -1
        Tile {
          theme: dlg.theme
          size: row.size
          y: parent.picked ? 0 : row.size * 0.22
          letter: modelData.isJoker ? "?" : modelData.letter
          points: modelData.points
          joker: modelData.isJoker
          highlight: parent.picked
          focused: dlg.cursor === index
          Behavior on y { NumberAnimation { duration: dlg.theme.anim(120) } }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { dlg.cursor = index; dlg.toggle(modelData.id) }
        }
      }
    }
  }

  Row {
    anchors.right: parent.right
    spacing: dlg.theme.space
    GameButton { theme: dlg.theme; text: dlg.theme.t("common.all"); variant: "ghost"; onClicked: dlg.selection = dlg.tiles.map(function(t) { return t.id }) }
    GameButton { theme: dlg.theme; text: dlg.theme.t("common.cancel"); variant: "ghost"; onClicked: dlg.cancelled() }
    GameButton {
      theme: dlg.theme
      variant: "primary"
      enabled: dlg.selection.length > 0
      text: dlg.selection.length > 0 ? dlg.theme.t("exchange.buttonN", { n: dlg.selection.length }) : dlg.theme.t("exchange.button")
      onClicked: dlg.confirmed(dlg.selection)
    }
  }
}
