import QtQuick
import qs.Commons

// Modal card over a scrim, in the shell's popup colours. Takes keyboard
// focus while open; Escape or a click outside dismisses it.
FocusScope {
  id: dialog

  property var theme
  property bool open: false
  property string title: ""
  property string message: ""
  property real preferredWidth: 440
  property bool dismissible: true
  default property alias content: body.data

  signal dismissed()

  anchors.fill: parent
  visible: open || card.opacity > 0.01
  z: 100

  onOpenChanged: if (open) Qt.callLater(function() { dialog.forceActiveFocus() })

  Keys.onEscapePressed: function(event) {
    if (dialog.dismissible) dialog.dismissed()
    event.accepted = true
  }

  Rectangle {
    anchors.fill: parent
    color: dialog.theme.scrim
    opacity: dialog.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: dialog.theme.anim(140) } }
    MouseArea {
      anchors.fill: parent
      onClicked: if (dialog.dismissible) dialog.dismissed()
    }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(dialog.preferredWidth, dialog.width - 2 * dialog.theme.spaceHuge)
    height: Math.min(column.implicitHeight + 2 * dialog.theme.padding, dialog.height - 2 * dialog.theme.spaceHuge)
    radius: dialog.theme.radius
    color: dialog.theme.background
    border.width: Math.max(1, dialog.theme.borderWidth)
    border.color: dialog.theme.followOmarchy ? Color.popups.border : dialog.theme.lineStrong
    opacity: dialog.open ? 1 : 0
    scale: dialog.open ? 1 : 0.97
    clip: true
    Behavior on opacity { NumberAnimation { duration: dialog.theme.anim(140) } }
    Behavior on scale { NumberAnimation { duration: dialog.theme.anim(160); easing.type: Easing.OutCubic } }

    MouseArea { anchors.fill: parent } // keep clicks inside the card

    Column {
      id: column
      x: dialog.theme.padding
      y: dialog.theme.padding
      width: parent.width - 2 * dialog.theme.padding
      spacing: dialog.theme.spaceLarge

      Text {
        visible: dialog.title !== ""
        width: parent.width
        text: dialog.title
        color: dialog.theme.foreground
        font.family: dialog.theme.fontFamily
        font.pixelSize: dialog.theme.fontHeading
        font.weight: Font.Bold
        wrapMode: Text.WordWrap
      }
      Text {
        visible: dialog.message !== ""
        width: parent.width
        text: dialog.message
        color: dialog.theme.muted
        font.family: dialog.theme.fontFamily
        font.pixelSize: dialog.theme.fontBody
        wrapMode: Text.WordWrap
        lineHeight: 1.15
      }
      Column {
        id: body
        width: parent.width
        spacing: dialog.theme.spaceLarge
      }
    }
  }
}
