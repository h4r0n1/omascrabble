import QtQuick

// A rounded group of related settings, with an optional small title.
Column {
  id: card

  property var theme
  property string title: ""
  default property alias content: inner.data

  spacing: theme.space

  Text {
    visible: card.title !== ""
    text: card.title
    color: card.theme.muted
    font.family: card.theme.fontFamily
    font.pixelSize: card.theme.fontSmall
    font.weight: Font.DemiBold
  }

  Rectangle {
    width: card.width
    height: inner.implicitHeight + 2 * pad
    readonly property int pad: 6
    radius: card.theme.radius > 0 ? card.theme.radius + 2 : 0
    color: card.theme.panel
    border.width: 1
    border.color: card.theme.line

    Column {
      id: inner
      x: parent.pad
      y: parent.pad
      width: parent.width - 2 * parent.pad
      spacing: 2
    }
  }
}
