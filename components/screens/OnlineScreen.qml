import QtQuick
import Quickshell.Io
import ".."

// Online play: invite a friend with a link, or join with the link you
// received. The two machines then deal the bag together and the game starts
// on both (docs/ONLINE.md).
FocusScope {
  id: page

  property var theme
  property var online       // OnlineService
  property var settings
  property var saves
  property var dictionary
  property string mode: "invite"   // invite | join
  property var gameConfig: null    // invite: the settings chosen in New game

  signal closed()
  signal acceptRequested(var config)

  function tr(key, args) { return theme.t(key, args) }

  readonly property var config: online && online.proposal ? online.proposal.config : null

  function configSummary(c) {
    if (!c) return ""
    var parts = [tr("setup.gameLanguage." + (c.gameLanguage === "en" ? "en" : "fr")), tr("dict." + (c.dictionary || "open-fr") + ".label")]
    parts.push(Number(c.timeMinutes) > 0 ? tr("common.minutes", { n: Number(c.timeMinutes) }) : tr("setup.time.none"))
    parts.push(tr("setup.validation." + (c.validation === "challenge" ? "challenge" : "immediate")))
    return parts.join("  ·  ")
  }

  function errorText() {
    var e = online ? online.lastError : null
    if (!e) return ""
    if (e.code === "link") return tr("online.error.link")
    if (e.code === "network") return tr("online.error.network", { message: e.message })
    if (e.code === "version") return tr("online.error.version")
    return e.message
  }

  function saveName(text) {
    if (!saves) return
    var next = JSON.parse(JSON.stringify(settings))
    next.online = Object.assign({}, settings.online, { name: text.trim().slice(0, 24) })
    saves.saveSettings(next)
  }

  onVisibleChanged: if (visible) {
    copied = false
    if (online) { online.start(); online.hello() }
    Qt.callLater(function() { (mode === "join" ? linkField : nameField).forceActiveFocus() })
  }

  property bool copied: false
  Process { id: copier }

  Keys.onEscapePressed: closed()

  Rectangle { anchors.fill: parent; color: page.theme.background }

  Flickable {
    anchors.fill: parent
    contentHeight: body.implicitHeight + 2 * page.theme.spaceHuge
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      width: Math.min(600, parent.width - 2 * page.theme.padding)
      x: (parent.width - width) / 2
      y: page.theme.spaceHuge
      spacing: page.theme.spaceLarge

      Row {
        spacing: page.theme.space
        GameButton { theme: page.theme; icon: "back"; variant: "ghost"; focusable: false; tooltip: page.tr("common.back"); onClicked: page.closed(); anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: page.tr(page.mode === "join" ? "online.title.join" : "online.title.invite")
          color: page.theme.foreground
          font.family: page.theme.fontFamily
          font.pixelSize: page.theme.fontDisplay
          font.weight: Font.Bold
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Not ready yet.
      Text {
        visible: !page.online || !page.online.checked
        text: page.tr("online.checking")
        color: page.theme.muted
        font.family: page.theme.fontFamily
        font.pixelSize: page.theme.fontBody
      }

      // toxcore (or Python) missing.
      SettingsCard {
        visible: !!page.online && page.online.checked && !page.online.available
        width: parent.width
        theme: page.theme
        Column {
          x: 10
          width: parent.width - 20
          topPadding: 10
          bottomPadding: 10
          spacing: page.theme.space
          Text {
            text: page.tr("online.missing.title")
            color: page.theme.foreground
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontHeading
            font.weight: Font.Bold
          }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.online && page.online.pythonMissing ? page.tr("online.missing.python") : page.tr("online.missing.text")
            color: page.theme.muted
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontBody
          }
          Rectangle {
            visible: !(page.online && page.online.pythonMissing)
            width: parent.width
            height: cmd.implicitHeight + 2 * page.theme.space
            radius: page.theme.radius
            color: page.theme.panelStrong
            TextEdit {
              id: cmd
              x: page.theme.space
              y: page.theme.space
              width: parent.width - 2 * page.theme.space
              readOnly: true
              selectByMouse: true
              text: "sudo pacman -S toxcore"
              color: page.theme.foreground
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontBody
            }
          }
          GameButton { theme: page.theme; variant: "secondary"; text: page.tr("online.recheck"); onClicked: page.online.recheck() }
        }
      }

      Column {
        visible: !!page.online && page.online.available
        width: parent.width
        spacing: page.theme.spaceLarge

        // Your name.
        Column {
          width: parent.width
          spacing: 6
          Text {
            text: page.tr("online.name")
            color: page.theme.muted
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontSmall
            font.weight: Font.DemiBold
          }
          NameField {
            id: nameField
            width: Math.min(320, parent.width)
            theme: page.theme
            text: page.online ? page.online.playerName : ""
            onEdited: function(t) { page.saveName(t) }
          }
          Text {
            text: page.tr("online.name.detail")
            color: page.theme.muted
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontCaption
          }
        }

        // ---------------------------------------------------- friends
        SettingsCard {
          visible: page.mode === "invite" && !!page.online && page.online.friends.length > 0 && page.online.stage !== "calling" && page.online.stage !== "dealing"
          width: parent.width
          theme: page.theme
          title: page.tr("online.friends")
          Repeater {
            model: page.online ? page.online.friends : []
            Item {
              required property var modelData
              required property int index
              width: parent.width
              height: page.theme.controlHeight + 8
              Rectangle {
                visible: index > 0
                width: parent.width - 12
                x: 6
                height: 1
                color: page.theme.line
              }
              Rectangle {
                id: dot
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8; radius: 4
                color: modelData.online ? page.theme.accent : page.theme.alpha(page.theme.foreground, 0.25)
              }
              Column {
                anchors.left: dot.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  text: modelData.name || "?"
                  color: page.theme.foreground
                  font.family: page.theme.fontFamily
                  font.pixelSize: page.theme.fontBody
                }
                Text {
                  text: page.tr(modelData.online ? "online.friend.online" : "online.friend.offline")
                  color: page.theme.muted
                  font.family: page.theme.fontFamily
                  font.pixelSize: page.theme.fontCaption
                }
              }
              GameButton {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                theme: page.theme
                variant: modelData.online ? "primary" : "secondary"
                icon: "play"
                text: page.tr("online.play")
                onClicked: page.online.call(modelData.id, page.gameConfig || {})
              }
            }
          }
        }

        // A call to a friend waiting for their answer.
        SettingsCard {
          visible: page.mode === "invite" && !!page.online && page.online.stage === "calling"
          width: parent.width
          theme: page.theme
          Text {
            x: 10
            width: parent.width - 20
            topPadding: 10
            bottomPadding: 10
            wrapMode: Text.WordWrap
            readonly property var c: page.online ? page.online.calling : null
            text: !c ? "" : page.tr(c.online ? "online.calling.sent" : "online.calling.offline", { name: page.online.friendName(c.friend) })
            color: page.theme.foreground
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontBody
          }
        }

        // ---------------------------------------------------- invite
        SettingsCard {
          visible: page.mode === "invite" && !!page.online && page.online.stage !== "calling"
          width: parent.width
          theme: page.theme
          title: page.tr(page.online && page.online.friends.length > 0 ? "online.link.new" : "online.link")
          Column {
            x: 10
            width: parent.width - 20
            topPadding: 10
            bottomPadding: 10
            spacing: page.theme.space
            Row {
              width: parent.width
              spacing: page.theme.space
              TextEdit {
                id: linkText
                width: parent.width - copyButton.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                text: page.online && page.online.link ? page.online.link : page.tr("online.link.making")
                color: page.online && page.online.link ? page.theme.foreground : page.theme.muted
                font.family: page.theme.fontFamily
                font.pixelSize: page.theme.fontSmall
              }
              GameButton {
                id: copyButton
                theme: page.theme
                variant: page.copied ? "secondary" : "primary"
                enabled: !!page.online && page.online.link !== ""
                text: page.tr(page.copied ? "online.copied" : "online.copy")
                onClicked: {
                  copier.command = ["wl-copy", "--", page.online.link]
                  copier.running = true
                  page.copied = true
                }
              }
            }
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: page.tr("online.link.help")
              color: page.theme.muted
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontSmall
            }
          }
        }

        // ---------------------------------------------------- join
        Column {
          visible: page.mode === "join" && (!page.online || (page.online.stage === "" || page.online.stage === "failed"))
          width: parent.width
          spacing: 6
          Text {
            text: page.tr("online.paste")
            color: page.theme.muted
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontSmall
            font.weight: Font.DemiBold
          }
          Row {
            width: parent.width
            spacing: page.theme.space
            NameField {
              id: linkField
              width: parent.width - joinButton.width - parent.spacing
              theme: page.theme
              maximumLength: 300
              placeholder: page.tr("online.paste.placeholder")
              onAccepted: if (text.trim() !== "") page.online.join(text, 102)
            }
            GameButton {
              id: joinButton
              theme: page.theme
              variant: "primary"
              enabled: linkField.text.trim() !== ""
              text: page.tr("online.join")
              onClicked: page.online.join(linkField.text, 102)
            }
          }
        }

        SettingsCard {
          visible: page.mode === "join" && !!page.online && page.online.stage === "proposal" && !!page.config
          width: parent.width
          theme: page.theme
          Column {
            x: 10
            width: parent.width - 20
            topPadding: 10
            bottomPadding: 10
            spacing: page.theme.space
            Text {
              text: page.online && page.online.proposal ? page.tr("online.proposal", { name: page.online.proposal.from }) : ""
              color: page.theme.foreground
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontHeading
              font.weight: Font.Bold
            }
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: page.configSummary(page.config)
              color: page.theme.muted
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontBody
            }
            Text {
              id: missingDict
              readonly property bool missing: !!page.config && !!page.dictionary && page.dictionary.installed[page.config.dictionary || "open-fr"] !== true
              visible: missing
              width: parent.width
              wrapMode: Text.WordWrap
              text: page.config ? page.tr("online.error.dictionary", { name: page.tr("dict." + (page.config.dictionary || "open-fr") + ".label") }) : ""
              color: page.theme.urgent
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontSmall
            }
            Row {
              spacing: page.theme.space
              GameButton { theme: page.theme; variant: "secondary"; text: page.tr("online.decline"); onClicked: page.online.decline() }
              GameButton {
                theme: page.theme
                variant: "primary"
                enabled: !missingDict.missing
                text: page.tr("online.accept")
                onClicked: page.acceptRequested(page.config)
              }
            }
          }
        }

        // ---------------------------------------------------- progress
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          readonly property string stage: page.online ? page.online.stage : ""
          visible: text !== ""
          text: stage === "calling" ? ""
            : stage === "inviting" ? page.tr("online.waiting")
            : stage === "joining" ? page.tr("online.connecting")
            : stage === "dealing" ? (page.online.peerName ? page.tr("online.joined", { name: page.online.peerName }) + "  " : "") + page.tr("online.dealing")
            : stage === "declined" ? page.tr("online.declined")
            : stage === "failed" ? page.tr("online.failed") + " " + page.errorText()
            : page.errorText()
          color: stage === "failed" || stage === "declined" ? page.theme.urgent : page.theme.muted
          font.family: page.theme.fontFamily
          font.pixelSize: page.theme.fontBody
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: page.tr("setup.online.note")
          color: page.theme.muted
          font.family: page.theme.fontFamily
          font.pixelSize: page.theme.fontCaption
        }

        GameButton {
          visible: !!page.online && page.online.stage !== "" && page.online.stage !== "playing"
          theme: page.theme
          variant: "ghost"
          text: page.tr("common.cancel")
          onClicked: { page.online.cancel(); page.closed() }
        }
      }
    }
  }
}
