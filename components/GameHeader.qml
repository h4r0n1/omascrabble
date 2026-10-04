import QtQuick

// ← Scrabble                                   ☰  ⚙  ⋯
Item {
  id: header

  property var theme
  property string title: "Omascrabble"
  property string subtitle: ""
  property bool showBack: true
  property bool historyAvailable: false
  property bool historyOpen: false

  signal backRequested()
  signal historyRequested()
  signal statsRequested()
  signal settingsRequested()
  signal menuRequested(real sceneX, real sceneY)

  implicitHeight: Math.max(titleColumn.implicitHeight, theme.controlHeight) + theme.spaceSmall

  Row {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: header.theme.space

    GameButton {
      visible: header.showBack
      theme: header.theme
      icon: "back"
      variant: "ghost"
      focusable: false
      tooltip: "Accueil"
      anchors.verticalCenter: parent.verticalCenter
      onClicked: header.backRequested()
    }

    Column {
      id: titleColumn
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Text {
        text: header.title
        color: header.theme.foreground
        font.family: header.theme.fontFamily
        font.pixelSize: header.theme.fontHeading
        font.weight: Font.Bold
        font.letterSpacing: 0.4
      }
      Text {
        visible: header.subtitle !== ""
        text: header.subtitle
        color: header.theme.muted
        font.family: header.theme.fontFamily
        font.pixelSize: header.theme.fontCaption
        elide: Text.ElideRight
        width: Math.min(implicitWidth, header.width * 0.6)
      }
    }
  }

  Row {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    GameButton {
      visible: header.historyAvailable
      theme: header.theme; icon: "history"; variant: "ghost"; focusable: false
      checked: header.historyOpen
      tooltip: "Historique des coups"
      onClicked: header.historyRequested()
    }
    GameButton { theme: header.theme; icon: "stats"; variant: "ghost"; focusable: false; tooltip: "Statistiques"; onClicked: header.statsRequested() }
    GameButton { theme: header.theme; icon: "settings"; variant: "ghost"; focusable: false; tooltip: "Réglages"; onClicked: header.settingsRequested() }
    GameButton {
      id: more
      theme: header.theme; icon: "more"; variant: "ghost"; focusable: false; tooltip: "Plus"
      onClicked: {
        var p = more.mapToItem(null, 0, more.height)
        header.menuRequested(p.x + more.width, p.y)
      }
    }
  }
}
