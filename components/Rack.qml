import QtQuick

// The player's rack: a shallow tray with up to seven tiles. Click lifts a
// tile (selection), dragging moves it to the board or to another slot.
// Tiles placed on the board leave the rack until they come back.
Item {
  id: rack

  property var theme
  property var controller
  property var tiles: []                // tile objects in display order
  property real tileSize: 48
  property int cursorIndex: -1
  property bool cursorVisible: false
  property bool hidden: false            // hot-seat handover
  property var markedIds: []             // exchange selection
  property int draggingId: -1

  signal tileClicked(int tileId, int index)
  signal dragStarted(int tileId, real sceneX, real sceneY)
  signal dragMoved(real sceneX, real sceneY)
  signal dragReleased(real sceneX, real sceneY)

  readonly property real spacing: Math.round(tileSize * 0.14)
  readonly property real trayPadding: Math.round(tileSize * 0.2)
  readonly property int slots: 7

  implicitWidth: slots * tileSize + (slots - 1) * spacing + 2 * trayPadding
  implicitHeight: tileSize + 2 * trayPadding + Math.round(tileSize * 0.1)

  function indexAtScene(sceneX, sceneY) {
    var p = tray.mapFromItem(null, sceneX, sceneY)
    if (p.y < -tileSize * 0.6 || p.y > tray.height + tileSize * 0.6) return -1
    var x = p.x - trayPadding
    var i = Math.floor((x + spacing / 2) / (tileSize + spacing))
    return Math.max(0, Math.min(Math.max(0, tiles.length - 1), i))
  }

  function containsScene(sceneX, sceneY) {
    var p = tray.mapFromItem(null, sceneX, sceneY)
    return p.x >= -tileSize * 0.3 && p.x <= tray.width + tileSize * 0.3 && p.y >= -tileSize * 0.5 && p.y <= tray.height + tileSize * 0.5
  }

  Rectangle {
    id: tray
    anchors.centerIn: parent
    width: rack.implicitWidth
    height: rack.implicitHeight
    radius: rack.theme.radius > 0 ? rack.theme.radius + 2 : 2
    color: rack.theme.panelStrong
    border.width: rack.theme.borderWidth
    border.color: rack.theme.line

    // inner shadow line, so the tray reads as a recess
    Rectangle {
      x: rack.trayPadding * 0.5
      y: 2
      width: parent.width - rack.trayPadding
      height: 1
      color: "#000000"
      opacity: rack.theme.dark ? 0.35 : 0.08
    }

    Text {
      visible: rack.hidden
      anchors.centerIn: parent
      text: rack.theme.t("rack.hidden")
      color: rack.theme.muted
      font.family: rack.theme.fontFamily
      font.pixelSize: rack.theme.fontBody
    }

    Repeater {
      model: rack.hidden ? 0 : rack.tiles.length
      Item {
        id: slot
        required property int index
        readonly property var t: rack.tiles[index]
        readonly property bool selected: rack.controller && t && rack.controller.selectedTileId === t.id
        readonly property bool marked: t && rack.markedIds.indexOf(t.id) !== -1
        x: rack.trayPadding + index * (rack.tileSize + rack.spacing)
        y: rack.trayPadding
        width: rack.tileSize
        height: rack.tileSize
        z: selected ? 2 : 1
        opacity: t && rack.draggingId === t.id ? 0.25 : 1

        Behavior on x { enabled: rack.theme.motionEnabled; NumberAnimation { duration: rack.theme.anim(160); easing.type: Easing.OutCubic } }

        Tile {
          id: face
          theme: rack.theme
          size: rack.tileSize
          // A tile still being dealt (online) shows blank until it's revealed.
          letter: slot.t && !slot.t.hidden ? (slot.t.isJoker ? "?" : slot.t.letter) : ""
          points: slot.t ? slot.t.points : 0
          showPoints: !(slot.t && slot.t.hidden)
          opacity: slot.t && slot.t.hidden ? 0.55 : 1
          joker: slot.t ? slot.t.isJoker : false
          selected: slot.selected
          highlight: slot.marked
          focused: rack.cursorVisible && rack.cursorIndex === slot.index
          y: slot.selected || slot.marked ? -Math.round(rack.tileSize * 0.16) : 0
          Behavior on y { enabled: rack.theme.motionEnabled; NumberAnimation { duration: rack.theme.anim(130); easing.type: Easing.OutCubic } }
        }
      }
    }
  }

  MouseArea {
    id: area
    anchors.fill: tray
    enabled: !rack.hidden
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    property int pressIndex: -1
    property point pressPos
    property bool dragging: false

    function indexAt(x) {
      var i = Math.floor((x - rack.trayPadding) / (rack.tileSize + rack.spacing))
      var within = (x - rack.trayPadding) - i * (rack.tileSize + rack.spacing)
      if (i < 0 || i >= rack.tiles.length || within > rack.tileSize) return -1
      return i
    }

    onPressed: function(mouse) {
      pressIndex = indexAt(mouse.x)
      pressPos = Qt.point(mouse.x, mouse.y)
      dragging = false
    }
    onPositionChanged: function(mouse) {
      if (!pressed || pressIndex < 0) return
      var s = area.mapToItem(null, mouse.x, mouse.y)
      if (!dragging && Math.abs(mouse.x - pressPos.x) + Math.abs(mouse.y - pressPos.y) > 6) {
        dragging = true
        rack.dragStarted(rack.tiles[pressIndex].id, s.x, s.y)
      }
      if (dragging) rack.dragMoved(s.x, s.y)
    }
    onReleased: function(mouse) {
      if (dragging) {
        var s = area.mapToItem(null, mouse.x, mouse.y)
        rack.dragReleased(s.x, s.y)
      } else if (pressIndex >= 0 && indexAt(mouse.x) === pressIndex) {
        rack.tileClicked(rack.tiles[pressIndex].id, pressIndex)
      }
      dragging = false
      pressIndex = -1
    }
  }

  Accessible.role: Accessible.List
  Accessible.name: theme.t("a11y.rack", { tiles: tiles.map(function(t) { return t.isJoker ? theme.t("a11y.joker") : t.letter }).join(", ") })
}
