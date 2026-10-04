import QtQuick
import ".."

// A yes/no question. `destructive` paints the confirm button in the urgent
// colour (resigning, abandoning a game).
Dialog {
  id: dlg

  property string confirmText: "Confirmer"
  property string cancelText: "Annuler"
  property bool destructive: false

  signal confirmed()
  signal cancelled()

  onDismissed: cancelled()

  Keys.onReturnPressed: confirmed()
  Keys.onEnterPressed: confirmed()

  Row {
    anchors.right: parent.right
    spacing: dlg.theme.space
    GameButton { theme: dlg.theme; text: dlg.cancelText; variant: "ghost"; onClicked: dlg.cancelled() }
    GameButton {
      theme: dlg.theme
      text: dlg.confirmText
      variant: "primary"
      danger: dlg.destructive
      onClicked: dlg.confirmed()
    }
  }
}
