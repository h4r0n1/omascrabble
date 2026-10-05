import QtQuick
import ".."

// Shown while saves and the dictionary load (a fraction of a second).
Rectangle {
  id: loading

  property var theme
  property var dictionary
  property var saves

  color: theme.background

  MouseArea { anchors.fill: parent }

  Column {
    anchors.centerIn: parent
    spacing: loading.theme.spaceLarge
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 6
      Repeater {
        model: ["M", "O", "T", "S"]
        Tile {
          required property var modelData
          required property int index
          theme: loading.theme
          size: 38
          letter: modelData
          points: [2, 1, 1, 1][index]
          SequentialAnimation on y {
            running: loading.visible && loading.theme.motionEnabled
            loops: Animation.Infinite
            PauseAnimation { duration: index * 120 }
            NumberAnimation { to: -6; duration: 260; easing.type: Easing.OutQuad }
            NumberAnimation { to: 0; duration: 260; easing.type: Easing.InQuad }
            PauseAnimation { duration: (3 - index) * 120 + 300 }
          }
        }
      }
    }
    Text {
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: loading.dictionary && loading.dictionary.status === "loading"
        ? loading.theme.t("loading.dictionary", { n: Math.round(loading.dictionary.progress * 100) })
        : loading.theme.t("loading.generic")
      color: loading.theme.muted
      font.family: loading.theme.fontFamily
      font.pixelSize: loading.theme.fontBody
    }
  }
}
