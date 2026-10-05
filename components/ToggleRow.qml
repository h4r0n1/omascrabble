import QtQuick
import qs.Commons

// A labelled on/off switch.
FocusScope {
  id: row

  property var theme
  property string label: ""
  property string detail: ""
  property bool checked: false

  signal toggled(bool value)

  activeFocusOnTab: true
  implicitHeight: Math.max(theme.controlHeight, textColumn.implicitHeight + 8)
  implicitWidth: 320

  Keys.onSpacePressed: toggled(!checked)
  Keys.onReturnPressed: toggled(!checked)

  Rectangle {
    anchors.fill: parent
    radius: row.theme.radius
    color: mouse.containsMouse || row.activeFocus ? Style.hoverFillFor(row.theme.foreground, row.theme.accent) : "transparent"
    border.width: row.activeFocus ? row.theme.borderWidth : 0
    border.color: row.theme.focusRing
  }

  Column {
    id: textColumn
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.right: track.left
    anchors.rightMargin: row.theme.spaceLarge
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: row.label
      color: row.theme.foreground
      font.family: row.theme.fontFamily
      font.pixelSize: row.theme.fontBody
      wrapMode: Text.WordWrap
    }
    Text {
      textFormat: Text.PlainText
      visible: row.detail !== ""
      width: parent.width
      text: row.detail
      color: row.theme.muted
      font.family: row.theme.fontFamily
      font.pixelSize: row.theme.fontSmall
      wrapMode: Text.WordWrap
    }
  }

  Rectangle {
    id: track
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter
    width: 34
    height: 18
    radius: row.theme.radius > 0 ? 9 : 2
    color: row.checked ? row.theme.accent : row.theme.alpha(row.theme.foreground, 0.16)
    Behavior on color { ColorAnimation { duration: row.theme.anim(120) } }
    Rectangle {
      width: 14; height: 14
      radius: row.theme.radius > 0 ? 7 : 1
      y: 2
      x: row.checked ? parent.width - width - 2 : 2
      color: row.checked ? row.theme.accentText : row.theme.foreground
      Behavior on x { NumberAnimation { duration: row.theme.anim(120); easing.type: Easing.OutCubic } }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: { row.forceActiveFocus(); row.toggled(!row.checked) }
  }

  Accessible.role: Accessible.CheckBox
  Accessible.name: label
  Accessible.checked: checked
}
