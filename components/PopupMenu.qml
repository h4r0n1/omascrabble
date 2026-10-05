import QtQuick
import qs.Commons

// A small dropdown of actions, anchored under the button that opened it.
Item {
  id: menu

  property var theme
  property var items: []          // [{ id, text, enabled }]
  property bool open: false
  property int cursor: 0

  signal activated(string id)

  anchors.fill: parent
  visible: open
  z: 120

  function openAt(sceneX, sceneY) {
    var p = menu.mapFromItem(null, sceneX, sceneY)
    panel.x = Math.max(8, Math.min(menu.width - panel.width - 8, p.x - panel.width))
    panel.y = Math.min(menu.height - panel.height - 8, p.y + 4)
    cursor = 0
    open = true
    focusCatcher.forceActiveFocus()
  }

  function choose(i) {
    var item = items[i]
    if (!item || item.enabled === false) return
    open = false
    activated(item.id)
  }

  MouseArea { anchors.fill: parent; onClicked: menu.open = false }

  Item {
    id: focusCatcher
    focus: menu.open
    Keys.onEscapePressed: menu.open = false
    Keys.onUpPressed: menu.cursor = Math.max(0, menu.cursor - 1)
    Keys.onDownPressed: menu.cursor = Math.min(menu.items.length - 1, menu.cursor + 1)
    Keys.onReturnPressed: menu.choose(menu.cursor)
    Keys.onEnterPressed: menu.choose(menu.cursor)
  }

  Rectangle {
    id: panel
    width: 260
    height: list.implicitHeight + 8
    radius: menu.theme.radius
    color: menu.theme.followOmarchy ? Color.menu.background : menu.theme.background
    border.width: Math.max(1, menu.theme.borderWidth)
    border.color: menu.theme.lineStrong

    Column {
      id: list
      x: 4
      y: 4
      width: parent.width - 8
      Repeater {
        model: menu.items
        Rectangle {
          required property var modelData
          required property int index
          width: list.width
          height: menu.theme.controlHeight
          radius: menu.theme.radius
          readonly property bool available: modelData.enabled !== false
          color: (mouse.containsMouse || menu.cursor === index) && available ? Style.hoverFillFor(menu.theme.foreground, menu.theme.accent) : "transparent"
          opacity: available ? 1 : 0.45
          Text {
            textFormat: Text.PlainText
            x: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.text
            color: menu.cursor === index && available ? menu.theme.accent : menu.theme.foreground
            font.family: menu.theme.fontFamily
            font.pixelSize: menu.theme.fontBody
          }
          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: menu.choose(index)
          }
        }
      }
    }
  }
}
