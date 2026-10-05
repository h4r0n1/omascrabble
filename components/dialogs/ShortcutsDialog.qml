import QtQuick
import ".."
import "../../app/settings.mjs" as SettingsModel

// Keyboard reference, from the live (configurable) shortcut map.
Dialog {
  id: dlg

  property var shortcuts: SettingsModel.DEFAULT_SHORTCUTS
  signal closed()

  title: theme.t("shortcuts.title")
  preferredWidth: 560
  onDismissed: closed()

  readonly property var fixedRows: [
    ["Tab", "shortcuts.fixed.tab"],
    ["← ↑ ↓ →", "shortcuts.fixed.arrows"],
    ["shift-arrows", "shortcuts.fixed.shiftArrows"],
    ["A … Z", "shortcuts.fixed.letters"],
    ["backspace", "shortcuts.fixed.backspace"]
  ]
  function keyText(k) {
    if (k === "shift-arrows") return theme.t("key.Shift") + " + ← →"
    if (k === "backspace") return theme.t("key.Backspace")
    return k
  }

  Column {
    width: parent.width
    spacing: 4
    Repeater {
      model: SettingsModel.SHORTCUT_ACTIONS
      Item {
        required property var modelData
        width: parent.width
        height: dlg.theme.fontBody * 1.9
        Text {
          text: dlg.theme.t("shortcut." + modelData)
          color: dlg.theme.foreground
          font.family: dlg.theme.fontFamily
          font.pixelSize: dlg.theme.fontBody
          anchors.verticalCenter: parent.verticalCenter
        }
        KeyCap {
          theme: dlg.theme
          text: SettingsModel.shortcutLabel(dlg.shortcuts[modelData], dlg.theme.t)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
    Rectangle { width: parent.width; height: 1; color: dlg.theme.line }
    Repeater {
      model: dlg.fixedRows
      Item {
        required property var modelData
        width: parent.width
        height: dlg.theme.fontBody * 1.9
        Text {
          text: dlg.theme.t(modelData[1])
          color: dlg.theme.muted
          font.family: dlg.theme.fontFamily
          font.pixelSize: dlg.theme.fontBody
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.68
          elide: Text.ElideRight
        }
        KeyCap {
          theme: dlg.theme
          text: dlg.keyText(modelData[0])
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  Row {
    anchors.right: parent.right
    GameButton { theme: dlg.theme; text: dlg.theme.t("common.close"); variant: "secondary"; onClicked: dlg.closed() }
  }
}
