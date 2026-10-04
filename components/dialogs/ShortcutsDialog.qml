import QtQuick
import ".."
import "../../app/settings.mjs" as SettingsModel

// Keyboard reference, from the live (configurable) shortcut map.
Dialog {
  id: dlg

  property var shortcuts: SettingsModel.DEFAULT_SHORTCUTS
  signal closed()

  title: "Raccourcis clavier"
  preferredWidth: 560
  onDismissed: closed()

  readonly property var fixedRows: [
    ["Tab", "Passer du chevalet au plateau, puis aux boutons"],
    ["← ↑ ↓ →", "Se déplacer sur le chevalet ou le plateau"],
    ["Maj + ← →", "Déplacer le jeton choisi sur le chevalet"],
    ["A … Z", "Sur le plateau : poser la lettre (le joker si besoin)"],
    ["Retour", "Sur le plateau : reprendre la dernière lettre posée"]
  ]

  Column {
    width: parent.width
    spacing: 4
    Repeater {
      model: Object.keys(SettingsModel.SHORTCUT_LABELS)
      Item {
        required property var modelData
        width: parent.width
        height: dlg.theme.fontBody * 1.9
        Text {
          text: SettingsModel.SHORTCUT_LABELS[modelData]
          color: dlg.theme.foreground
          font.family: dlg.theme.fontFamily
          font.pixelSize: dlg.theme.fontBody
          anchors.verticalCenter: parent.verticalCenter
        }
        KeyCap {
          theme: dlg.theme
          text: SettingsModel.shortcutLabel(dlg.shortcuts[modelData])
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
          text: modelData[1]
          color: dlg.theme.muted
          font.family: dlg.theme.fontFamily
          font.pixelSize: dlg.theme.fontBody
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.68
          elide: Text.ElideRight
        }
        KeyCap {
          theme: dlg.theme
          text: modelData[0]
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  Row {
    anchors.right: parent.right
    GameButton { theme: dlg.theme; text: "Fermer"; variant: "secondary"; onClicked: dlg.closed() }
  }
}
