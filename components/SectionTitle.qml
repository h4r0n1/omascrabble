import QtQuick

// Small caps section heading with a hairline, as in the shell's panels.
Item {
  id: section
  property var theme
  property string text: ""
  implicitHeight: label.implicitHeight + 10
  implicitWidth: 300
  Text {
    textFormat: Text.PlainText
    id: label
    anchors.left: parent.left
    anchors.bottom: rule.top
    anchors.bottomMargin: 4
    text: section.text.toUpperCase()
    color: section.theme.muted
    font.family: section.theme.fontFamily
    font.pixelSize: section.theme.fontCaption
    font.weight: Font.Bold
    font.letterSpacing: 1.4
  }
  Rectangle {
    id: rule
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    color: section.theme.line
  }
}
