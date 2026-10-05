import QtQuick

// A number with its label, for the statistics view.
Rectangle {
  id: tile
  property var theme
  property string label: ""
  property string value: ""
  property string detail: ""
  property bool compact: false

  height: column.implicitHeight + 2 * (compact ? theme.space + 2 : theme.padding * 0.8)
  radius: theme.radius
  color: theme.panel
  border.width: theme.borderWidth
  border.color: theme.line

  Column {
    id: column
    x: tile.compact ? tile.theme.space + 4 : tile.theme.padding
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - 2 * x
    spacing: 2
    Text {
      textFormat: Text.PlainText
      text: tile.label.toUpperCase()
      width: parent.width
      elide: Text.ElideRight
      color: tile.theme.muted
      font.family: tile.theme.fontFamily
      font.pixelSize: tile.theme.fontCaption
      font.weight: Font.Bold
      font.letterSpacing: 1
    }
    Text {
      textFormat: Text.PlainText
      text: tile.value
      width: parent.width
      elide: Text.ElideRight
      color: tile.theme.foreground
      font.family: tile.theme.fontFamily
      font.pixelSize: tile.compact ? tile.theme.fontHeading : tile.theme.fontDisplay
      font.weight: Font.Bold
    }
    Text {
      textFormat: Text.PlainText
      visible: !tile.compact
      text: tile.detail !== "" ? tile.detail : " "
      width: parent.width
      elide: Text.ElideRight
      color: tile.theme.muted
      font.family: tile.theme.fontFamily
      font.pixelSize: tile.theme.fontSmall
    }
  }
}
