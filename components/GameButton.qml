import QtQuick
import qs.Commons

// A button in the Omarchy idiom (flat surface, shell border and state
// tokens, shell radius and font) with the variants a game needs:
//   primary    accent fill for the move that ends a turn (JOUER)
//   secondary  bordered, for the other turn actions
//   ghost      borderless, for toolbars
// Keyboard: focusable through Tab; Enter/Space activate.
Rectangle {
  id: button

  property var theme
  property string text: ""
  property string icon: ""
  property string variant: "secondary"
  property bool compact: false
  property string tooltip: ""
  property string shortcutHint: ""
  property bool checked: false
  property bool focusable: true
  // Focus drawn by a parent that runs its own keyboard model (the game
  // screen), independent of Qt's active focus.
  property bool keyboardFocus: false
  // A primary button for an irreversible action (resign, abandon).
  property bool danger: false
  readonly property color fill: danger ? theme.urgent : theme.accent
  readonly property bool showFocus: activeFocus || keyboardFocus

  signal clicked()

  readonly property bool hot: mouse.containsMouse && enabled
  readonly property bool primary: variant === "primary"
  readonly property color ink: !enabled ? Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.35)
    : primary ? (theme.lum(fill) > 0.55 ? "#151515" : "#ffffff")
    : checked ? theme.accent
    : theme.foreground

  activeFocusOnTab: focusable && enabled
  implicitHeight: compact ? Math.round(theme.controlHeight * 0.86) : theme.controlHeight
  implicitWidth: Math.max(implicitHeight, row.implicitWidth + (text !== "" ? Style.spacing.controlPaddingX * 2.4 : Style.spacing.controlPaddingY * 2))
  radius: theme.radius
  opacity: enabled ? 1 : 0.6

  color: {
    if (primary) {
      if (!enabled) return theme.alpha(fill, 0.35)
      if (mouse.pressed) return Qt.darker(fill, 1.18)
      if (hot) return Qt.lighter(fill, 1.08)
      return fill
    }
    if (mouse.pressed) return Style.pressedFillFor(theme.foreground, theme.accent)
    if (showFocus) return Style.focusFillFor(theme.foreground, theme.accent)
    if (hot) return Style.hoverFillFor(theme.foreground, theme.accent)
    if (checked) return Style.selectedFillFor(theme.foreground, theme.accent)
    return variant === "secondary" ? Style.normalFillFor(theme.foreground, theme.accent) : "transparent"
  }
  border.width: primary ? 0 : showFocus ? Math.max(2, theme.borderWidth) : variant === "secondary" || hot ? theme.borderWidth : 0
  border.color: showFocus ? theme.focusRing
    : hot ? Style.hoverBorderFor(theme.foreground, theme.accent)
    : Style.normalBorderFor(theme.foreground, theme.accent)

  Behavior on color { ColorAnimation { duration: theme.anim(110) } }

  // Focus ring for the primary button sits outside the fill.
  Rectangle {
    visible: button.primary && button.showFocus
    anchors.fill: parent
    anchors.margins: -3
    radius: button.radius + 3
    color: "transparent"
    border.width: 2
    border.color: button.theme.focusRing
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.spacing.sm + 1
    Icon {
      visible: button.icon !== ""
      name: button.icon
      color: button.ink
      width: Math.round(button.theme.fontBody * 1.35)
      height: width
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      textFormat: Text.PlainText
      visible: button.text !== ""
      text: button.text
      color: button.ink
      font.family: button.theme.fontFamily
      font.pixelSize: button.compact ? button.theme.fontSmall : button.theme.fontBody
      font.weight: button.primary ? Font.Bold : Font.DemiBold
      font.letterSpacing: button.primary ? 0.6 : 0.2
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  ToolTipBubble {
    theme: button.theme
    text: button.tooltip + (button.shortcutHint !== "" ? "  ·  " + button.shortcutHint : "")
    shown: button.tooltip !== "" && mouse.containsMouse
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (button.enabled) button.clicked()
  }

  Keys.onReturnPressed: if (enabled) clicked()
  Keys.onEnterPressed: if (enabled) clicked()
  Keys.onSpacePressed: if (enabled) clicked()

  Accessible.role: Accessible.Button
  Accessible.name: text !== "" ? text : tooltip
  Accessible.onPressAction: if (enabled) clicked()
}
