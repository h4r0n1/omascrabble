import QtQuick

// Three dots breathing in turn: the AI is thinking. Static when motion is off.
Row {
  id: dots
  property var theme
  property color color: theme.accent
  property bool running: true
  spacing: Math.max(2, Math.round(size * 0.45))
  property real size: 5

  Repeater {
    model: 3
    Rectangle {
      required property int index
      width: dots.size
      height: dots.size
      radius: dots.size / 2
      color: dots.color
      opacity: 0.35
      SequentialAnimation on opacity {
        running: dots.running && dots.theme.motionEnabled
        loops: Animation.Infinite
        PauseAnimation { duration: index * 160 }
        NumberAnimation { to: 1; duration: 320; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.35; duration: 320; easing.type: Easing.InOutSine }
        PauseAnimation { duration: (2 - index) * 160 }
      }
    }
  }
}
