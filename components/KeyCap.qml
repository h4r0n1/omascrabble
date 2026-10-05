import QtQuick

// A key label, e.g. "Ctrl + S".
Rectangle {
  id: cap
  property var theme
  property string text: ""
  implicitWidth: label.implicitWidth + 14
  implicitHeight: label.implicitHeight + 6
  width: implicitWidth
  height: implicitHeight
  radius: Math.max(2, theme.radius)
  color: theme.panelStrong
  border.width: 1
  border.color: theme.line
  Text {
    textFormat: Text.PlainText
    id: label
    anchors.centerIn: parent
    text: cap.text
    color: cap.theme.foreground
    font.family: cap.theme.fontFamily
    font.pixelSize: cap.theme.fontSmall
    font.weight: Font.DemiBold
  }
}
