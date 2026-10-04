import QtQuick

// What the move on the board is worth, word by word:
//
//   MAISON      18
//   QI          22
//   AS           4
//   ─────────────
//   TOTAL       44
//
// Invalid words are marked; a Scrabble shows its bonus line; a move that
// cannot be played says why.
Item {
  id: preview

  property var theme
  property var result: null           // validator result
  property bool showValidity: true
  property bool compact: false
  property string emptyText: "Placez des lettres sur le plateau."
  property bool clickable: false
  signal wordActivated(string word)

  implicitHeight: content.implicitHeight
  implicitWidth: 240

  readonly property bool structural: result && !result.valid && (!result.words || result.words.length === 0)

  Column {
    id: content
    width: parent.width
    spacing: preview.compact ? 2 : 4

    Text {
      visible: !preview.result
      width: parent.width
      text: preview.emptyText
      color: preview.theme.muted
      font.family: preview.theme.fontFamily
      font.pixelSize: preview.theme.fontSmall
      wrapMode: Text.WordWrap
    }

    Text {
      visible: preview.structural
      width: parent.width
      text: preview.result && preview.result.message ? preview.result.message : ""
      color: preview.theme.urgent
      font.family: preview.theme.fontFamily
      font.pixelSize: preview.theme.fontSmall
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: preview.result && preview.result.words ? preview.result.words : []
      Item {
        required property var modelData
        width: content.width
        height: wordText.implicitHeight
        readonly property bool bad: preview.showValidity && modelData.valid === false
        Text {
          id: wordText
          text: modelData.notation || modelData.word
          color: parent.bad ? preview.theme.urgent : preview.theme.foreground
          font.family: preview.theme.fontFamily
          font.pixelSize: preview.theme.fontBody
          font.weight: modelData.isMain ? Font.Bold : Font.Normal
          font.strikeout: parent.bad
          font.letterSpacing: 0.8
        }
        MouseArea {
          anchors.fill: parent
          enabled: preview.clickable
          hoverEnabled: preview.clickable
          cursorShape: preview.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: preview.wordActivated(modelData.word)
        }
        Text {
          visible: parent.bad
          anchors.left: wordText.right
          anchors.leftMargin: 6
          anchors.verticalCenter: wordText.verticalCenter
          text: "mot invalide"
          color: preview.theme.urgent
          font.family: preview.theme.fontFamily
          font.pixelSize: preview.theme.fontCaption
        }
        Text {
          anchors.right: parent.right
          text: modelData.score
          color: preview.theme.foreground
          font.family: preview.theme.fontFamily
          font.pixelSize: preview.theme.fontBody
          font.features: { "tnum": 1 }
        }
      }
    }

    Item {
      visible: !!(preview.result && preview.result.bingo)
      width: content.width
      height: bonusText.implicitHeight
      Text {
        id: bonusText
        text: "Scrabble (7 lettres)"
        color: preview.theme.accent
        font.family: preview.theme.fontFamily
        font.pixelSize: preview.theme.fontBody
        font.weight: Font.DemiBold
      }
      Text {
        anchors.right: parent.right
        text: "+ " + (preview.result ? preview.result.bonus : 0)
        color: preview.theme.accent
        font.family: preview.theme.fontFamily
        font.pixelSize: preview.theme.fontBody
        font.weight: Font.DemiBold
      }
    }

    Rectangle {
      visible: !!(preview.result && preview.result.words && preview.result.words.length > 0)
      width: content.width
      height: 1
      color: preview.theme.line
    }

    Item {
      visible: !!(preview.result && preview.result.words && preview.result.words.length > 0)
      width: content.width
      height: totalText.implicitHeight
      Text {
        id: totalText
        text: "TOTAL"
        color: preview.theme.muted
        font.family: preview.theme.fontFamily
        font.pixelSize: preview.theme.fontSmall
        font.weight: Font.Bold
        font.letterSpacing: 1.2
        anchors.verticalCenter: totalValue.verticalCenter
      }
      Text {
        id: totalValue
        anchors.right: parent.right
        text: preview.result ? preview.result.score + " pts" : ""
        color: preview.result && preview.result.valid ? preview.theme.foreground : preview.theme.muted
        font.family: preview.theme.fontFamily
        font.pixelSize: preview.theme.fontHeading
        font.weight: Font.Bold
      }
    }

    Text {
      visible: !!(preview.result && !preview.result.valid && !preview.structural && preview.result.reason !== "INVALID_WORD" && preview.result.reason !== "INVALID_CROSS_WORD")
      width: parent.width
      text: preview.result && preview.result.message ? preview.result.message : ""
      color: preview.theme.urgent
      font.family: preview.theme.fontFamily
      font.pixelSize: preview.theme.fontSmall
      wrapMode: Text.WordWrap
    }
  }
}
