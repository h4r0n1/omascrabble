import QtQuick

// One square of the board. It binds to plain values from the controller's
// per-cell snapshot, so a move only repaints the squares that changed. The
// tile is created on demand.
Item {
  id: cell

  property var theme
  property int row: 0
  property int col: 0
  property string premium: "NONE"
  property real size: 32

  // From the controller snapshot.
  property string kind: "empty"     // empty | board | pending | hint
  property string letter: ""
  property int points: 0
  property bool joker: false
  property bool lastMove: false
  property bool highlight: false
  property bool invalid: false

  // Interaction state, from the board.
  property bool cursor: false
  property bool hovered: false
  property bool ghostVisible: false
  property string ghostLetter: ""
  property int ghostPoints: 0
  property bool ghostJoker: false
  property bool blocked: false      // hover over an illegal square
  property bool dropTarget: false
  property bool showLabels: true
  property bool pulse: false        // premium flash after a move

  width: size
  height: size

  readonly property bool occupied: kind !== "empty"
  readonly property real innerRadius: Math.max(1, theme.tileRadius(size) * 0.7)

  Rectangle {
    id: square
    anchors.fill: parent
    radius: cell.innerRadius
    color: cell.theme.premiumColor(cell.premium)
    border.width: cell.blocked ? Math.max(1.5, cell.size * 0.05) : cell.dropTarget ? Math.max(2, cell.size * 0.06) : 0
    border.color: cell.blocked ? cell.theme.alpha(cell.theme.urgent, 0.7) : cell.theme.accent

    Rectangle {
      // hover wash
      anchors.fill: parent
      radius: parent.radius
      color: cell.theme.foreground
      opacity: cell.hovered && !cell.occupied && !cell.blocked ? 0.08 : 0
      Behavior on opacity { NumberAnimation { duration: cell.theme.anim(90) } }
    }

    Text {
      visible: cell.showLabels && !cell.occupied && cell.premium !== "NONE" && !cell.ghostVisible
      anchors.centerIn: parent
      text: cell.theme.premiumLabel(cell.premium)
      color: cell.theme.premiumInk(cell.premium)
      font.family: cell.theme.fontFamily
      font.pixelSize: cell.premium === "CENTER" ? Math.round(cell.size * 0.56) : Math.max(7, Math.round(cell.size * 0.3))
      font.weight: Font.Bold
      font.letterSpacing: cell.premium === "CENTER" ? 0 : 0.4
    }
    // Without labels the star still marks the centre.
    Text {
      visible: !cell.showLabels && cell.premium === "CENTER" && !cell.occupied
      anchors.centerIn: parent
      text: "★"
      color: cell.theme.premiumInk(cell.premium)
      font.pixelSize: Math.round(cell.size * 0.5)
    }
  }

  // Premium flash when a move spends this square.
  Rectangle {
    id: flash
    anchors.fill: parent
    anchors.margins: -Math.round(cell.size * 0.08)
    radius: cell.innerRadius + 2
    color: "transparent"
    border.width: Math.max(2, cell.size * 0.07)
    border.color: cell.theme.premiumColor(cell.premium)
    opacity: 0
    SequentialAnimation {
      id: flashAnim
      NumberAnimation { target: flash; property: "opacity"; to: 0.95; duration: cell.theme.anim(140) }
      PauseAnimation { duration: cell.theme.anim(260) }
      NumberAnimation { target: flash; property: "opacity"; to: 0; duration: cell.theme.anim(420) }
    }
  }
  onPulseChanged: if (pulse && theme.motionEnabled && premium !== "NONE") flashAnim.restart()

  Loader {
    id: tileLoader
    active: cell.occupied
    anchors.fill: parent
    sourceComponent: Tile {
      id: tileItem
      theme: cell.theme
      size: cell.size
      letter: cell.letter
      points: cell.points
      joker: cell.joker
      pending: cell.kind === "pending"
      ghost: cell.kind === "hint"
      lastMove: cell.lastMove
      highlight: cell.highlight
      invalid: cell.invalid
      focused: cell.cursor
      transformOrigin: Item.Center
      Component.onCompleted: {
        if (cell.theme.motionEnabled && (cell.kind === "pending" || cell.kind === "board")) {
          scale = 1.18
          opacity = 0.2
          popIn.start()
        }
      }
      ParallelAnimation {
        id: popIn
        NumberAnimation { target: tileItem; property: "scale"; to: 1; duration: cell.theme.anim(170); easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        NumberAnimation { target: tileItem; property: "opacity"; to: 1; duration: cell.theme.anim(110) }
      }
    }
  }

  // Ghost of the selected tile under the pointer: a preview of the drop.
  Tile {
    visible: cell.ghostVisible && !cell.occupied
    theme: cell.theme
    size: cell.size
    letter: cell.ghostLetter
    points: cell.ghostPoints
    joker: cell.ghostJoker
    ghost: true
  }

  // Keyboard cursor
  Rectangle {
    visible: cell.cursor && !cell.occupied
    anchors.fill: parent
    anchors.margins: -1
    radius: cell.innerRadius + 1
    color: "transparent"
    border.width: Math.max(2, Math.round(cell.size * 0.07))
    border.color: cell.theme.focusRing
  }

  Accessible.role: Accessible.Cell
  Accessible.name: String.fromCharCode(65 + row) + (col + 1) + ", " + theme.premiumName(premium)
    + (occupied ? ", " + (joker ? "joker " : "") + letter : ", vide")
}
