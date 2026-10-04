import QtQuick
import QtQuick.Shapes

// Line icons drawn as vector paths on a 24-unit grid, coloured by the theme.
// Drawn rather than taken from a font so they look the same whatever font
// the user picked, at any size.
Item {
  id: icon

  property string name: ""
  property color color: "white"
  property real lineWidth: 1.7

  implicitWidth: 18
  implicitHeight: 18

  readonly property var paths: ({
    back: "M 15 18 L 9 12 L 15 6",
    close: "M 6 6 L 18 18 M 18 6 L 6 18",
    check: "M 5 12.5 L 10 17.5 L 19 7",
    more: "M 5 12 m -1.6 0 a 1.6 1.6 0 1 0 3.2 0 a 1.6 1.6 0 1 0 -3.2 0 M 12 12 m -1.6 0 a 1.6 1.6 0 1 0 3.2 0 a 1.6 1.6 0 1 0 -3.2 0 M 19 12 m -1.6 0 a 1.6 1.6 0 1 0 3.2 0 a 1.6 1.6 0 1 0 -3.2 0",
    settings: "M 4 7 H 20 M 4 12 H 20 M 4 17 H 20 M 9 7 m -2 0 a 2 2 0 1 0 4 0 a 2 2 0 1 0 -4 0 M 15 12 m -2 0 a 2 2 0 1 0 4 0 a 2 2 0 1 0 -4 0 M 8 17 m -2 0 a 2 2 0 1 0 4 0 a 2 2 0 1 0 -4 0",
    shuffle: "M 4 7 H 7.5 C 12 7 12 17 16.5 17 H 20 M 4 17 H 7.5 C 9.5 17 10.6 15.2 11.3 13.4 M 12.7 10.6 C 13.4 8.8 14.5 7 16.5 7 H 20 M 17 4 L 20 7 L 17 10 M 17 14 L 20 17 L 17 20",
    recall: "M 9 14 L 4 9 L 9 4 M 4 9 H 14.5 A 5.5 5.5 0 0 1 14.5 20 H 10",
    hint: "M 9.5 18 H 14.5 M 10.5 21 H 13.5 M 12 3 A 6 6 0 0 0 8.2 13.6 C 8.9 14.3 9.5 15.2 9.5 16 H 14.5 C 14.5 15.2 15.1 14.3 15.8 13.6 A 6 6 0 0 0 12 3 Z",
    exchange: "M 7 4 L 4 7 L 7 10 M 4 7 H 17 M 17 14 L 20 17 L 17 20 M 20 17 H 7",
    pass: "M 5 6 L 11 12 L 5 18 M 13 6 L 19 12 L 13 18",
    flag: "M 5 21 V 4 M 5 4 H 17.5 L 15 8 L 17.5 12 H 5",
    history: "M 9 6 H 20 M 9 12 H 20 M 9 18 H 20 M 4.5 6 h 0.01 M 4.5 12 h 0.01 M 4.5 18 h 0.01",
    stats: "M 3 20 H 21 M 6 20 V 13 M 11 20 V 6 M 16 20 V 10 M 21 20 V 3",
    play: "M 5 12 H 19 M 13 6 L 19 12 L 13 18",
    plus: "M 12 5 V 19 M 5 12 H 19",
    book: "M 4 19 V 5 A 2 2 0 0 1 6 3 H 20 V 17 H 6 A 2 2 0 0 0 4 19 A 2 2 0 0 0 6 21 H 20 V 17",
    sound: "M 4 9.5 H 7.5 L 12 5.5 V 18.5 L 7.5 14.5 H 4 Z M 15.5 9 A 4 4 0 0 1 15.5 15 M 18 6.5 A 7.5 7.5 0 0 1 18 17.5",
    keyboard: "M 3 6.5 H 21 V 17.5 H 3 Z M 7 10 h 0.01 M 10.3 10 h 0.01 M 13.7 10 h 0.01 M 17 10 h 0.01 M 8 14 H 16",
    challenge: "M 12 3 L 21 19 H 3 Z M 12 9.5 V 13.5 M 12 16.5 h 0.01",
    replay: "M 4 12 A 8 8 0 1 0 6.3 6.3 M 4 4 V 9 H 9",
    prev: "M 15 18 L 9 12 L 15 6",
    next: "M 9 6 L 15 12 L 9 18",
    first: "M 17 18 L 11 12 L 17 6 M 7 6 V 18",
    last: "M 7 6 L 13 12 L 7 18 M 17 6 V 18",
    trophy: "M 8 4 H 16 V 9 A 4 4 0 0 1 8 9 Z M 8 5.5 H 5 A 3 3 0 0 0 8 10.5 M 16 5.5 H 19 A 3 3 0 0 1 16 10.5 M 12 13 V 17 M 8.5 20 H 15.5 M 9.5 17 H 14.5 V 20 H 9.5 Z",
    info: "M 12 3 A 9 9 0 1 0 12 21 A 9 9 0 1 0 12 3 Z M 12 11 V 16.5 M 12 7.6 h 0.01"
  })

  Shape {
    id: shape
    width: 24
    height: 24
    anchors.centerIn: parent
    scale: Math.min(icon.width, icon.height) / 24
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: icon.color
      fillColor: "transparent"
      strokeWidth: icon.lineWidth / Math.max(0.1, shape.scale)
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: icon.paths[icon.name] || "" }
    }
  }
}
