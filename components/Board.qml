import QtQuick
import "../engine/board.mjs" as BoardModel
import "../engine/notation.mjs" as Notation

// The 15 × 15 board with optional coordinates (rows A–O, columns 1–15, the
// French Scrabble convention). One mouse area serves the whole grid and maps
// the pointer to a square, rather than 225 separate handlers.
Item {
  id: board

  property var theme
  property var controller
  property bool showCoordinates: true
  // "fr": rows A–O, columns 1–15; "en": columns A–O, rows 1–15.
  property string notation: "fr"
  property bool showLabels: true
  property bool cursorVisible: false
  property int cursorRow: 7
  property int cursorCol: 7
  property string direction: "H"
  property int dropRow: -1
  property int dropCol: -1
  property var flashCells: ({})       // index → true for the premium flash
  property int flashSerial: 0

  signal cellClicked(int row, int col)
  signal cellHovered(int row, int col)
  signal tilePressed(int row, int col, real sceneX, real sceneY)
  signal dragMoved(real sceneX, real sceneY)
  signal dragReleased(real sceneX, real sceneY)

  // Geometry without binding loops: total = labels + frame + 15 cells + 14
  // gaps, with labels and gaps proportional to the cell.
  readonly property real available: Math.min(width, height)
  readonly property real labelRatio: showCoordinates ? 0.62 : 0
  readonly property real gapRatio: 0.065
  readonly property real framePad: Math.max(3, Math.round(available * 0.012))
  readonly property int cellSize: Math.max(8, Math.floor((available - 2 * framePad) / (15 + 14 * gapRatio + labelRatio)))
  readonly property int gap: Math.max(1, Math.round(cellSize * gapRatio))
  readonly property int labelSize: showCoordinates ? Math.round(cellSize * labelRatio) : 0
  readonly property int gridSize: cellSize * 15 + gap * 14
  readonly property int boardSize: gridSize + 2 * framePad + labelSize

  implicitWidth: boardSize
  implicitHeight: boardSize

  function cellAt(x, y) {
    var gx = x - grid.x - frame.x
    var gy = y - grid.y - frame.y
    if (gx < 0 || gy < 0 || gx >= gridSize || gy >= gridSize) return null
    var col = Math.floor(gx / (cellSize + gap))
    var row = Math.floor(gy / (cellSize + gap))
    if (row < 0 || row > 14 || col < 0 || col > 14) return null
    return { row: row, col: col }
  }

  function cellAtScene(sceneX, sceneY) {
    var p = board.mapFromItem(null, sceneX, sceneY)
    return cellAt(p.x, p.y)
  }

  function cellCenterScene(row, col) {
    return frame.mapToItem(null, grid.x + col * (cellSize + gap) + cellSize / 2, grid.y + row * (cellSize + gap) + cellSize / 2)
  }

  function flash(indices) {
    var next = {}
    for (var i = 0; i < indices.length; i++) next[indices[i]] = true
    flashCells = next
    flashSerial++
    flashReset.restart()
  }

  Timer { id: flashReset; interval: 50; onTriggered: board.flashCells = ({}) }

  width: boardSize
  height: boardSize

  // Column numbers
  Row {
    visible: board.showCoordinates
    x: frame.x + grid.x
    y: 0
    spacing: board.gap
    Repeater {
      model: 15
      Text {
        textFormat: Text.PlainText
        width: board.cellSize
        height: board.labelSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: Notation.colLabel(index, board.notation)
        color: board.cursorVisible && board.cursorCol === index ? board.theme.accent : board.theme.muted
        font.family: board.theme.fontFamily
        font.pixelSize: Math.max(8, Math.round(board.cellSize * 0.34))
      }
    }
  }

  // Row letters
  Column {
    visible: board.showCoordinates
    x: 0
    y: frame.y + grid.y
    spacing: board.gap
    Repeater {
      model: 15
      Text {
        textFormat: Text.PlainText
        width: board.labelSize
        height: board.cellSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: Notation.rowLabel(index, board.notation)
        color: board.cursorVisible && board.cursorRow === index ? board.theme.accent : board.theme.muted
        font.family: board.theme.fontFamily
        font.pixelSize: Math.max(8, Math.round(board.cellSize * 0.34))
      }
    }
  }

  Rectangle {
    id: frame
    x: board.labelSize
    y: board.labelSize
    width: board.gridSize + 2 * board.framePad
    height: width
    radius: board.theme.radius > 0 ? Math.min(board.theme.radius + 2, board.cellSize * 0.4) : 0
    color: board.theme.boardFrame
    border.width: board.theme.highContrast ? 2 : 0
    border.color: board.theme.foreground

    Grid {
      id: grid
      x: board.framePad
      y: board.framePad
      columns: 15
      rowSpacing: board.gap
      columnSpacing: board.gap

      Repeater {
        model: 225
        BoardCell {
          required property int index
          readonly property var info: board.controller ? board.controller.cells[index] : null
          readonly property int r: Math.floor(index / 15)
          readonly property int c: index % 15
          readonly property bool isHover: board.controller && board.controller.hoverCell !== null
            && board.controller.hoverCell.row === r && board.controller.hoverCell.col === c
          readonly property var hoverTile: isHover && board.controller.selectedTileId >= 0 ? board.controller.tile(board.controller.selectedTileId) : null
          theme: board.theme
          row: r
          col: c
          size: board.cellSize
          premium: BoardModel.PREMIUM_LAYOUT[index]
          cellLabel: Notation.cellLabel(r, c, board.notation)
          kind: info ? info.kind : "empty"
          letter: info ? info.letter : ""
          points: info ? info.points : 0
          joker: info ? info.joker : false
          lastMove: info ? info.last : false
          highlight: info ? info.highlight : false
          invalid: info ? info.invalid : false
          showLabels: board.showLabels
          cursor: board.cursorVisible && board.cursorRow === r && board.cursorCol === c
          hovered: isHover
          ghostVisible: hoverTile !== null && kind === "empty" && board.controller.placementProblem(r, c) === ""
          ghostLetter: hoverTile ? (hoverTile.isJoker ? "?" : hoverTile.letter) : ""
          ghostPoints: hoverTile ? hoverTile.points : 0
          ghostJoker: hoverTile ? hoverTile.isJoker : false
          blocked: hoverTile !== null && kind === "empty" && board.controller.placementProblem(r, c) !== ""
          dropTarget: board.dropRow === r && board.dropCol === c
          pulse: board.flashCells[index] === true
        }
      }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    property var pressCell: null
    property point pressPos
    property bool dragging: false

    onPositionChanged: function(mouse) {
      var hit = board.cellAt(mouse.x, mouse.y)
      if (pressed && pressCell && !dragging) {
        if (Math.abs(mouse.x - pressPos.x) + Math.abs(mouse.y - pressPos.y) > 6) {
          var info = board.controller.cells[pressCell.row * 15 + pressCell.col]
          if (info && info.kind === "pending") {
            dragging = true
            var s = area.mapToItem(null, mouse.x, mouse.y)
            board.tilePressed(pressCell.row, pressCell.col, s.x, s.y)
          }
        }
      }
      if (dragging) {
        var sc = area.mapToItem(null, mouse.x, mouse.y)
        board.dragMoved(sc.x, sc.y)
        return
      }
      board.cellHovered(hit ? hit.row : -1, hit ? hit.col : -1)
    }
    onExited: if (!dragging) board.cellHovered(-1, -1)
    onPressed: function(mouse) {
      pressCell = board.cellAt(mouse.x, mouse.y)
      pressPos = Qt.point(mouse.x, mouse.y)
      dragging = false
    }
    onReleased: function(mouse) {
      if (dragging) {
        var s = area.mapToItem(null, mouse.x, mouse.y)
        board.dragReleased(s.x, s.y)
      } else if (pressCell) {
        var hit = board.cellAt(mouse.x, mouse.y)
        if (hit && hit.row === pressCell.row && hit.col === pressCell.col) board.cellClicked(hit.row, hit.col)
      }
      dragging = false
      pressCell = null
    }
  }
}
