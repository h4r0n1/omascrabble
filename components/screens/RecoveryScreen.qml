import QtQuick
import ".."

// The dictionary could not be loaded: explain, offer a retry, never crash.
Rectangle {
  id: recovery

  property var theme
  property var dictionary
  property var saves

  color: theme.background
  MouseArea { anchors.fill: parent }

  Column {
    anchors.centerIn: parent
    width: Math.min(560, parent.width - 2 * recovery.theme.padding)
    spacing: recovery.theme.spaceLarge

    Icon {
      name: "book"
      color: recovery.theme.urgent
      width: 36
      height: 36
    }
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: recovery.dictionary && recovery.dictionary.status === "missing" ? "Dictionnaire introuvable" : "Le dictionnaire n’a pas pu être chargé"
      color: recovery.theme.foreground
      font.family: recovery.theme.fontFamily
      font.pixelSize: recovery.theme.fontDisplay
      font.weight: Font.Bold
    }
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      lineHeight: 1.2
      text: "Sans dictionnaire, les mots ne peuvent pas être vérifiés et l’ordinateur ne peut pas jouer. Votre partie sauvegardée n’est pas touchée.\n\n"
        + "Si vous avez supprimé ou modifié les fichiers du plugin, réinstallez-le (omarchy plugin update omarchy-scrabble) ; pour un ODS installé à la main, vérifiez le fichier dans ~/.local/share/omarchy-scrabble/dictionaries."
      color: recovery.theme.muted
      font.family: recovery.theme.fontFamily
      font.pixelSize: recovery.theme.fontBody
    }
    Rectangle {
      width: parent.width
      height: detail.implicitHeight + 2 * recovery.theme.space
      radius: recovery.theme.radius
      color: recovery.theme.panel
      border.width: 1
      border.color: recovery.theme.line
      Text {
        id: detail
        x: recovery.theme.space
        y: recovery.theme.space
        width: parent.width - 2 * recovery.theme.space
        wrapMode: Text.WrapAnywhere
        text: recovery.dictionary ? recovery.dictionary.errorMessage : ""
        color: recovery.theme.foreground
        font.family: recovery.theme.fontFamily
        font.pixelSize: recovery.theme.fontSmall
      }
    }
    Row {
      spacing: recovery.theme.space
      GameButton { theme: recovery.theme; variant: "primary"; text: "Réessayer"; onClicked: recovery.dictionary.retry() }
      GameButton {
        theme: recovery.theme
        variant: "secondary"
        text: "Revenir au lexique ouvert"
        visible: recovery.dictionary && recovery.dictionary.dictionaryId !== "open-fr"
        onClicked: recovery.dictionary.load("open-fr")
      }
    }
  }
}
