import QtQuick
import QtQuick.Controls
import qs.Commons

// Tooltip in the shell's [tooltip] colours, shown after a short delay.
ToolTip {
  id: tip

  property var theme
  property bool shown: false

  visible: shown && text !== ""
  delay: 450
  padding: 0
  background: Rectangle {
    color: Color.tooltip.background
    border.width: 1
    border.color: Color.tooltip.border
    radius: tip.theme ? tip.theme.radius : 0
  }
  contentItem: Text {
    text: tip.text
    textFormat: Text.PlainText
    color: Color.tooltip.text
    font.family: tip.theme ? tip.theme.fontFamily : Style.font.family
    font.pixelSize: tip.theme ? tip.theme.fontSmall : Style.font.bodySmall
    leftPadding: Style.spacing.controlPaddingX
    rightPadding: Style.spacing.controlPaddingX
    topPadding: Style.spacing.controlPaddingY
    bottomPadding: Style.spacing.controlPaddingY
  }
}
