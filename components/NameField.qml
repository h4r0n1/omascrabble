import QtQuick
import qs.Commons

// A short single-line text field (player names).
Rectangle {
  id: field

  property var theme
  property alias text: input.text
  signal edited(string text)

  implicitHeight: theme.controlHeight
  radius: theme.radius
  color: Style.normalFillFor(theme.foreground, theme.accent)
  border.width: input.activeFocus ? Math.max(2, theme.borderWidth) : theme.borderWidth
  border.color: input.activeFocus ? theme.focusRing : theme.line

  TextInput {
    id: input
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.rightMargin: Style.spacing.controlPaddingX
    verticalAlignment: TextInput.AlignVCenter
    color: field.theme.foreground
    selectionColor: field.theme.alpha(field.theme.accent, 0.4)
    font.family: field.theme.fontFamily
    font.pixelSize: field.theme.fontBody
    maximumLength: 24
    activeFocusOnTab: true
    clip: true
    onTextEdited: field.edited(text)
  }
}
