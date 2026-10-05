import QtQuick
import qs.Commons

// A set of mutually exclusive options (radio buttons), laid out as rows or
// as a single line of chips. Tab focuses the group; arrows change the value.
FocusScope {
  id: group

  property var theme
  property string title: ""
  property var options: []         // [{ value, label, detail, enabled, badge }]
  property var value
  property bool inline: false

  signal picked(var value)

  activeFocusOnTab: true
  implicitWidth: 320
  implicitHeight: column.implicitHeight

  function indexOfValue() {
    for (var i = 0; i < options.length; i++) if (options[i].value === value) return i
    return -1
  }
  function step(d) {
    var i = indexOfValue()
    for (var k = 0; k < options.length; k++) {
      i = (i + d + options.length) % options.length
      if (options[i].enabled !== false) { picked(options[i].value); return }
    }
  }
  Keys.onLeftPressed: step(-1)
  Keys.onUpPressed: step(-1)
  Keys.onRightPressed: step(1)
  Keys.onDownPressed: step(1)

  Column {
    id: column
    width: parent.width
    spacing: group.theme.space

    Text {
      textFormat: Text.PlainText
      visible: group.title !== ""
      text: group.title.toUpperCase()
      color: group.activeFocus ? group.theme.accent : group.theme.muted
      font.family: group.theme.fontFamily
      font.pixelSize: group.theme.fontCaption
      font.weight: Font.Bold
      font.letterSpacing: 1.2
    }

    Flow {
      width: parent.width
      spacing: group.inline ? group.theme.space : 4
      Repeater {
        model: group.options
        Rectangle {
          id: option
          required property var modelData
          readonly property bool selected: modelData.value === group.value
          readonly property bool available: modelData.enabled !== false
          readonly property bool hot: mouse.containsMouse && available
          width: group.inline ? row.implicitWidth + 2 * Style.spacing.controlPaddingX : column.width
          height: group.inline ? group.theme.controlHeight : Math.max(group.theme.controlHeight, row.implicitHeight + 2 * Style.spacing.controlPaddingY + 4)
          radius: group.theme.radius
          opacity: available ? 1 : 0.5
          color: selected ? Style.selectedFillFor(group.theme.foreground, group.theme.accent)
            : hot ? Style.hoverFillFor(group.theme.foreground, group.theme.accent)
            : "transparent"
          border.width: selected || hot || group.inline ? group.theme.borderWidth : 0
          border.color: selected ? group.theme.alpha(group.theme.accent, group.activeFocus ? 1 : 0.6) : group.theme.line

          Row {
            id: row
            x: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.controlGap
            Rectangle {
              visible: !group.inline
              width: 14; height: 14; radius: 7
              anchors.verticalCenter: parent.verticalCenter
              color: "transparent"
              border.width: 1.5
              border.color: option.selected ? group.theme.accent : group.theme.lineStrong
              Rectangle {
                anchors.centerIn: parent
                width: 6; height: 6; radius: 3
                color: group.theme.accent
                visible: option.selected
              }
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              Row {
                spacing: 8
                Text {
                  textFormat: Text.PlainText
                  text: option.modelData.label
                  color: option.selected ? group.theme.foreground : group.theme.foreground
                  font.family: group.theme.fontFamily
                  font.pixelSize: group.theme.fontBody
                  font.weight: option.selected ? Font.Bold : Font.Normal
                }
                Rectangle {
                  visible: !!option.modelData.badge
                  height: badgeText.implicitHeight + 2
                  width: badgeText.implicitWidth + 10
                  radius: Math.max(2, group.theme.radius)
                  color: group.theme.alpha(group.theme.accent, 0.16)
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    textFormat: Text.PlainText
                    id: badgeText
                    anchors.centerIn: parent
                    text: option.modelData.badge || ""
                    color: group.theme.accent
                    font.family: group.theme.fontFamily
                    font.pixelSize: group.theme.fontCaption
                    font.weight: Font.Bold
                  }
                }
              }
              Text {
                textFormat: Text.PlainText
                visible: !group.inline && !!option.modelData.detail
                text: option.modelData.detail || ""
                color: group.theme.muted
                font.family: group.theme.fontFamily
                font.pixelSize: group.theme.fontSmall
                width: Math.min(implicitWidth, column.width - 60)
                wrapMode: Text.WordWrap
              }
            }
          }

          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: option.available ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (option.available) { group.forceActiveFocus(); group.picked(option.modelData.value) }
          }
          Accessible.role: Accessible.RadioButton
          Accessible.name: option.modelData.label
          Accessible.checked: option.selected
        }
      }
    }
  }
}
