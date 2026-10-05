import QtQuick

// A letter tile: ivory face, a darker lower edge for thickness, a soft offset
// shadow. No textures, no heavy 3D — just enough depth to feel like an
// object you could pick up.
//
// A joker keeps its own look (letter in a different ink, a small dot, no
// points) so it never passes for a normal tile.
Item {
  id: tile

  property var theme
  property string letter: ""
  property int points: 0
  property bool joker: false
  property real size: 40
  property bool pending: false
  property bool selected: false
  property bool lastMove: false
  property bool invalid: false
  property bool highlight: false
  property bool ghost: false
  property bool showPoints: true
  property bool focused: false

  width: size
  height: size

  readonly property real edge: Math.max(1, Math.round(size * 0.075))
  readonly property real r: theme.tileRadius(size)

  // Shadow
  Rectangle {
    visible: !tile.ghost
    x: tile.selected ? tile.size * 0.02 : 0
    y: tile.selected ? tile.size * 0.12 : tile.size * 0.045
    width: tile.size
    height: tile.size
    radius: tile.r
    color: tile.theme.tileShadow
    opacity: tile.selected ? 0.75 : 0.55
  }

  Item {
    id: body
    width: tile.size
    height: tile.size
    opacity: tile.ghost ? 0.42 : 1

    // Edge (the tile's thickness, seen at the bottom)
    Rectangle {
      anchors.fill: parent
      radius: tile.r
      color: tile.theme.tileEdge
    }

    // Face
    Rectangle {
      id: face
      width: parent.width
      height: parent.height - tile.edge
      radius: tile.r
      gradient: Gradient {
        GradientStop { position: 0; color: tile.theme.tileTop }
        GradientStop { position: 1; color: tile.theme.tileBottom }
      }
      // Bevel light on the top edge.
      Rectangle {
        x: tile.r * 0.6
        y: 1
        width: parent.width - tile.r * 1.2
        height: 1
        color: "#ffffff"
        opacity: tile.theme.dark ? 0.22 : 0.55
        visible: tile.size >= 22
      }

      Text {
        textFormat: Text.PlainText
        id: glyph
        text: tile.letter
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: tile.showPoints && !tile.joker ? -tile.size * 0.05 : 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -tile.size * 0.015
        color: tile.joker ? tile.theme.jokerInk : tile.theme.tileInk
        font.family: tile.theme.fontFamily
        font.pixelSize: Math.round(tile.size * 0.56)
        font.weight: Font.Bold
        font.italic: tile.joker
      }

      Text {
        textFormat: Text.PlainText
        visible: tile.showPoints && !tile.joker && tile.size >= 20
        text: tile.points
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Math.max(1, Math.round(tile.size * 0.07))
        anchors.bottomMargin: Math.max(0, Math.round(tile.size * 0.03))
        color: tile.theme.tilePoints
        font.family: tile.theme.fontFamily
        font.pixelSize: Math.max(7, Math.round(tile.size * (tile.points >= 10 ? 0.2 : 0.24)))
        font.weight: Font.DemiBold
      }

      // Joker mark
      Rectangle {
        visible: tile.joker
        width: Math.max(3, Math.round(tile.size * 0.12))
        height: width
        radius: width / 2
        x: Math.round(tile.size * 0.1)
        y: Math.round(tile.size * 0.1)
        color: tile.theme.jokerInk
        opacity: 0.85
      }
    }

    // State rings
    Rectangle {
      anchors.fill: parent
      anchors.margins: -1
      radius: tile.r + 1
      color: "transparent"
      visible: tile.invalid || tile.pending || tile.selected || tile.focused || tile.highlight
      border.width: tile.invalid || tile.selected || tile.focused ? Math.max(2, Math.round(tile.size * 0.06)) : Math.max(1.5, tile.size * 0.045)
      border.color: tile.invalid ? tile.theme.invalidRing
        : tile.focused ? tile.theme.focusRing
        : tile.highlight ? tile.theme.accent
        : tile.theme.pendingRing
    }

    // Last move: a quiet underline in the accent colour.
    Rectangle {
      visible: tile.lastMove && !tile.pending && !tile.invalid
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: tile.edge + Math.max(1, tile.size * 0.04)
      width: tile.size * 0.42
      height: Math.max(2, Math.round(tile.size * 0.05))
      radius: height / 2
      color: tile.theme.lastMoveRing
    }
  }

  Accessible.role: Accessible.StaticText
  Accessible.name: tile.joker ? tile.theme.t("a11y.jokerLetter", { letter: tile.letter }) : tile.theme.t("a11y.letter", { letter: tile.letter, points: tile.points })
}
