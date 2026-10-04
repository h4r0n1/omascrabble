import QtQuick
import QtQuick.Controls as QQC
import ".."

// Definitions of the words a move formed, from the optional Wiktionnaire
// pack. Without the pack it explains how to install it.
Dialog {
  id: dlg

  property var definitions: null       // DefinitionsService
  property var forms: ({})             // tile word → accented spellings
  property var words: []               // tile words, main word first
  property string subtitle: ""
  property var results: ({})           // tile word → lookup result

  signal closed()

  title: "Définitions"
  message: subtitle
  preferredWidth: 560
  onDismissed: closed()
  Keys.onReturnPressed: closed()

  readonly property string installCommand: "python3 ~/.config/omarchy/plugins/omascrabble/tools/install-definitions.py"

  onOpenChanged: if (open) load()
  onWordsChanged: if (open) load()

  function load() {
    results = ({})
    if (!definitions) return
    words.forEach(function(w) {
      definitions.lookup(w, function(r) {
        var next = Object.assign({}, dlg.results)
        next[w] = r
        dlg.results = next
      })
    })
  }

  Flickable {
    width: parent.width
    height: Math.min(contentHeight, (dlg.height > 0 ? dlg.height : 600) * 0.62)
    contentHeight: body.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

    Column {
      id: body
      width: parent.width - 12
      spacing: dlg.theme.spaceLarge

      Column {
        visible: !!dlg.definitions && dlg.definitions.checked && !dlg.definitions.installed
        width: parent.width
        spacing: dlg.theme.space
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Les définitions ne sont pas installées. Elles sont facultatives : une seule commande les télécharge (environ 700 Mo, une fois) et les prépare pour un usage hors ligne."
          color: dlg.theme.muted
          font.family: dlg.theme.fontFamily
          font.pixelSize: dlg.theme.fontBody
        }
        Rectangle {
          width: parent.width
          height: cmd.implicitHeight + 2 * dlg.theme.space
          radius: dlg.theme.radius
          color: dlg.theme.panel
          border.width: 1
          border.color: dlg.theme.line
          TextEdit {
            id: cmd
            x: dlg.theme.space
            y: dlg.theme.space
            width: parent.width - 2 * dlg.theme.space
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            text: dlg.installCommand
            color: dlg.theme.foreground
            font.family: dlg.theme.fontFamily
            font.pixelSize: dlg.theme.fontSmall
          }
        }
      }

      Repeater {
        model: dlg.words
        Column {
          required property var modelData
          readonly property var result: dlg.results[modelData]
          readonly property var spellings: dlg.forms[modelData] || []
          width: body.width
          spacing: 6

          Row {
            spacing: 10
            Text {
              text: modelData
              color: dlg.theme.foreground
              font.family: dlg.theme.fontFamily
              font.pixelSize: dlg.theme.fontHeading
              font.weight: Font.Bold
              font.letterSpacing: 1
            }
            Text {
              visible: spellings.length > 0
              text: spellings.join(", ")
              color: dlg.theme.muted
              font.family: dlg.theme.fontFamily
              font.pixelSize: dlg.theme.fontBody
              font.italic: true
              anchors.baseline: parent.children[0].baseline
            }
          }

          Text {
            visible: !!dlg.definitions && dlg.definitions.installed && !!result && result.entries.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Pas de définition dans le Wiktionnaire pour ce mot."
            color: dlg.theme.muted
            font.family: dlg.theme.fontFamily
            font.pixelSize: dlg.theme.fontSmall
          }

          Repeater {
            model: result ? result.entries : []
            Column {
              required property var modelData
              width: body.width
              spacing: 3
              Text {
                text: modelData.p !== "" ? modelData.p.toUpperCase() + "  ·  " + modelData.w : modelData.w
                color: dlg.theme.accent
                font.family: dlg.theme.fontFamily
                font.pixelSize: dlg.theme.fontCaption
                font.weight: Font.Bold
                font.letterSpacing: 1
              }
              Repeater {
                model: modelData.d
                Text {
                  required property var modelData
                  required property int index
                  width: body.width
                  wrapMode: Text.WordWrap
                  text: (index + 1) + ". " + modelData
                  color: dlg.theme.foreground
                  font.family: dlg.theme.fontFamily
                  font.pixelSize: dlg.theme.fontBody
                  lineHeight: 1.1
                }
              }
              // A form of another word: show that word's meaning too.
              Repeater {
                model: modelData.of && result && result.lemmas[modelData.of] ? result.lemmas[modelData.of] : []
                Column {
                  required property var modelData
                  width: body.width
                  spacing: 2
                  leftPadding: 14
                  Text {
                    text: modelData.w + (modelData.p !== "" ? "  ·  " + modelData.p.toLowerCase() : "")
                    color: dlg.theme.muted
                    font.family: dlg.theme.fontFamily
                    font.pixelSize: dlg.theme.fontSmall
                    font.weight: Font.Bold
                  }
                  Repeater {
                    model: modelData.d
                    Text {
                      required property var modelData
                      required property int index
                      width: body.width - 14
                      wrapMode: Text.WordWrap
                      text: (index + 1) + ". " + modelData
                      color: dlg.theme.muted
                      font.family: dlg.theme.fontFamily
                      font.pixelSize: dlg.theme.fontSmall
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Item {
    width: parent.width
    height: closeButton.height
    Text {
      visible: !!dlg.definitions && dlg.definitions.installed
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - closeButton.width - 12
      wrapMode: Text.WordWrap
      text: "Définitions : Wiktionnaire, CC BY-SA 4.0 (via Kaikki.org)"
      color: dlg.theme.muted
      font.family: dlg.theme.fontFamily
      font.pixelSize: dlg.theme.fontCaption
    }
    GameButton {
      id: closeButton
      anchors.right: parent.right
      theme: dlg.theme
      text: "Fermer"
      variant: "secondary"
      onClicked: dlg.closed()
    }
  }
}
