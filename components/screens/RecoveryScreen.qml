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
      text: recovery.theme.t(recovery.dictionary && recovery.dictionary.status === "missing" ? "recovery.missing" : "recovery.failed")
      color: recovery.theme.foreground
      font.family: recovery.theme.fontFamily
      font.pixelSize: recovery.theme.fontDisplay
      font.weight: Font.Bold
    }
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      lineHeight: 1.2
      text: recovery.theme.t("recovery.text")
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
      GameButton { theme: recovery.theme; variant: "primary"; text: recovery.theme.t("common.retry"); onClicked: recovery.dictionary.retry() }
      GameButton {
        theme: recovery.theme
        variant: "secondary"
        text: recovery.theme.t("recovery.backToOpen")
        visible: recovery.dictionary && recovery.dictionary.dictionaryId.indexOf("open-") !== 0
        onClicked: recovery.dictionary.load(recovery.dictionary.dictionaryId === "collins" ? "open-en" : "open-fr")
      }
    }
  }
}
