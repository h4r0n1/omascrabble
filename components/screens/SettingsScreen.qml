import QtQuick
import QtQuick.Controls
import qs.Commons
import ".."
import "../../app/format.mjs" as Format
import "../../app/settings.mjs" as SettingsModel
import "../../ai/difficulty.mjs" as Difficulty

// Réglages: a sidebar of sections and one page per section (tabs across the
// top when the window is narrow). Every change is saved immediately.
FocusScope {
  id: page

  property var theme
  property var saves
  property var dictionary
  property var definitions: null
  property var online: null              // OnlineService
  property string section: ""            // asked for by the caller ("about"…)
  property string current: "gameplay"    // page on show; kept between visits
  property string rebinding: ""          // shortcut being captured
  property bool keyboardNav: false       // draw the focus ring only for keys

  signal closed()

  readonly property var sections: [
    { id: "gameplay", icon: "grid" },
    { id: "computer", icon: "cpu" },
    { id: "appearance", icon: "palette" },
    { id: "language", icon: "globe" },
    { id: "accessibility", icon: "eye" },
    { id: "shortcuts", icon: "keyboard" },
    { id: "definitions", icon: "book" },
    { id: "online", icon: "people" },
    { id: "about", icon: "info" }
  ]
  readonly property bool narrow: width < 760
  readonly property var s: saves ? saves.settings : SettingsModel.normalizeSettings({})

  function tr(key, args) { return theme.t(key, args) }
  function set(path, value) { saves.saveSettings(SettingsModel.withSetting(s, path, value)) }
  function indexOf(id) {
    for (var i = 0; i < sections.length; i++) if (sections[i].id === id) return i
    return 0
  }
  function show(id) {
    rebinding = ""
    if (id === "online" && online) online.hello()   // fetch the friends list
    if (current !== id) fadeIn.restart()
    current = id
    flick.contentY = 0
  }

  onVisibleChanged: if (visible) {
    rebinding = ""
    keyboardNav = false
    if (section !== "") show(section)
    section = ""
    Qt.callLater(function() { nav.forceActiveFocus() })
  }

  Keys.onPressed: function(event) {
    if (page.rebinding !== "") {
      if (event.key === Qt.Key_Escape) { page.rebinding = ""; event.accepted = true; return }
      var shortcut = SettingsModel.shortcutFromEvent(event, Qt)
      if (shortcut !== "") {
        var next = Object.assign({}, page.s.shortcuts)
        next[page.rebinding] = shortcut
        page.set("shortcuts", next)
        page.rebinding = ""
      }
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Escape) { page.closed(); event.accepted = true }
  }

  Rectangle { anchors.fill: parent; color: page.theme.background }

  // One entry of the sidebar (or a tab when narrow).
  component NavItem: Rectangle {
    id: item
    property var theme
    property string icon: ""
    property string label: ""
    property bool selected: false
    property bool focused: false
    property bool compact: false
    signal activated()

    implicitWidth: row.implicitWidth + 2 * theme.space + 6
    implicitHeight: theme.controlHeight + 4
    radius: theme.radius
    color: selected ? theme.alpha(theme.accent, 0.14)
         : mouse.containsMouse ? Style.hoverFillFor(theme.foreground, theme.accent) : "transparent"
    border.width: focused ? theme.borderWidth : 0
    border.color: theme.focusRing
    Behavior on color { ColorAnimation { duration: item.theme.anim(120) } }

    // Selection marker: a bar on the left, or under the label for tabs.
    Rectangle {
      visible: item.selected
      color: item.theme.accent
      radius: 1.5
      x: item.compact ? item.theme.space : 0
      y: item.compact ? parent.height - 3 : 6
      width: item.compact ? parent.width - 2 * item.theme.space : 3
      height: item.compact ? 3 : parent.height - 12
    }

    Row {
      id: row
      x: item.theme.space + 4
      anchors.verticalCenter: parent.verticalCenter
      spacing: item.theme.space
      Icon {
        name: item.icon
        color: item.selected ? item.theme.accent : item.theme.muted
        width: 18
        height: 18
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        textFormat: Text.PlainText
        text: item.label
        color: item.selected ? item.theme.foreground : item.theme.muted
        font.family: item.theme.fontFamily
        font.pixelSize: item.theme.fontBody
        font.weight: item.selected ? Font.DemiBold : Font.Normal
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: item.activated()
    }
    Accessible.role: Accessible.PageTab
    Accessible.name: label
    Accessible.selected: selected
  }

  Item {
    id: frame
    width: Math.min(1040, page.width - 2 * page.theme.padding)
    x: (page.width - width) / 2
    y: page.theme.spaceHuge
    height: page.height - y

    // Title row.
    Row {
      id: header
      spacing: page.theme.space
      GameButton { theme: page.theme; icon: "back"; variant: "ghost"; focusable: false; tooltip: page.tr("common.back"); onClicked: page.closed(); anchors.verticalCenter: parent.verticalCenter }
      Text {
        textFormat: Text.PlainText
        text: page.tr("settings.title")
        color: page.theme.foreground
        font.family: page.theme.fontFamily
        font.pixelSize: page.theme.fontDisplay
        font.weight: Font.Bold
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Section list: Up/Down (Left/Right as tabs) to move, Enter or Tab to go
    // into the page.
    FocusScope {
      id: nav
      activeFocusOnTab: true
      y: header.height + page.theme.spaceLarge
      width: page.narrow ? frame.width : 220
      height: page.narrow ? tabs.height : sidebar.implicitHeight

      function step(delta) {
        page.keyboardNav = true
        var i = Math.max(0, Math.min(page.sections.length - 1, page.indexOf(page.current) + delta))
        page.show(page.sections[i].id)
      }
      function enter() {
        page.keyboardNav = true
        var next = nav.nextItemInFocusChain(true)
        if (next) next.forceActiveFocus()
      }
      Keys.onUpPressed: step(-1)
      Keys.onDownPressed: step(1)
      Keys.onLeftPressed: if (page.narrow) step(-1)
      Keys.onRightPressed: page.narrow ? step(1) : enter()
      Keys.onReturnPressed: enter()
      Keys.onEnterPressed: enter()

      Column {
        id: sidebar
        visible: !page.narrow
        width: parent.width
        spacing: 2
        Repeater {
          model: page.sections
          NavItem {
            required property var modelData
            width: sidebar.width
            theme: page.theme
            icon: modelData.icon
            label: page.tr("settings.nav." + modelData.id)
            selected: page.current === modelData.id
            focused: selected && nav.activeFocus && page.keyboardNav
            onActivated: { page.keyboardNav = false; page.show(modelData.id); nav.forceActiveFocus() }
          }
        }
      }

      Flickable {
        id: tabs
        visible: page.narrow
        width: parent.width
        height: tabRow.height
        contentWidth: tabRow.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        Row {
          id: tabRow
          spacing: 2
          Repeater {
            model: page.sections
            NavItem {
              required property var modelData
              required property int index
              theme: page.theme
              compact: true
              icon: modelData.icon
              label: page.tr("settings.nav." + modelData.id)
              selected: page.current === modelData.id
              focused: selected && nav.activeFocus && page.keyboardNav
              onActivated: { page.keyboardNav = false; page.show(modelData.id); nav.forceActiveFocus() }
              onSelectedChanged: if (selected && page.narrow)
                tabs.contentX = Math.max(0, Math.min(tabs.contentWidth - tabs.width, x - (tabs.width - width) / 2))
            }
          }
        }
      }
    }

    Rectangle {
      visible: !page.narrow
      x: nav.width + page.theme.spaceLarge
      y: nav.y
      width: 1
      height: frame.height - nav.y - page.theme.spaceLarge
      color: page.theme.line
    }

    Flickable {
      id: flick
      x: page.narrow ? 0 : nav.width + 2 * page.theme.spaceLarge + 1
      y: page.narrow ? nav.y + nav.height + page.theme.spaceLarge : nav.y
      width: frame.width - x
      height: frame.height - y
      contentHeight: body.implicitHeight + page.theme.spaceHuge
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      NumberAnimation { id: fadeIn; target: body; property: "opacity"; from: 0.25; to: 1; duration: page.theme.anim(160); easing.type: Easing.OutCubic }

      Column {
        id: body
        width: Math.min(660, flick.width - 14)
        spacing: page.theme.spaceLarge

        // Page heading.
        Column {
          width: parent.width
          spacing: 4
          Text {
            textFormat: Text.PlainText
            text: page.tr("settings.nav." + page.current)
            color: page.theme.foreground
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontHeading
            font.weight: Font.Bold
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.tr("settings.nav." + page.current + ".detail")
            color: page.theme.muted
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontSmall
          }
        }

        // ------------------------------------------------------- Jeu
        Column {
          visible: page.current === "gameplay"
          width: parent.width
          spacing: page.theme.spaceLarge
          SettingsCard {
            width: parent.width
            theme: page.theme
            title: page.tr("settings.group.aids")
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.confirmMoves"); detail: page.tr("settings.confirmMoves.detail"); checked: page.s.gameplay.confirmMoves; onToggled: function(v) { page.set("gameplay.confirmMoves", v) } }
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.assisted"); detail: page.tr("settings.assisted.detail"); checked: page.s.gameplay.assistedPlacement; onToggled: function(v) { page.set("gameplay.assistedPlacement", v) } }
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.scorePreview"); checked: page.s.gameplay.showScorePreview; onToggled: function(v) { page.set("gameplay.showScorePreview", v) } }
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.wordValidation"); detail: page.tr("settings.wordValidation.detail"); checked: page.s.gameplay.showWordValidation; onToggled: function(v) { page.set("gameplay.showWordValidation", v) } }
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.coordinates"); checked: page.s.gameplay.showCoordinates; onToggled: function(v) { page.set("gameplay.showCoordinates", v) } }
          }
          SettingsCard {
            width: parent.width
            theme: page.theme
            title: page.tr("settings.group.game")
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.sounds"); detail: page.tr("settings.sounds.detail"); checked: page.s.gameplay.sounds; onToggled: function(v) { page.set("gameplay.sounds", v) } }
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.pauseClock"); checked: page.s.gameplay.pauseClockWhenHidden; onToggled: function(v) { page.set("gameplay.pauseClockWhenHidden", v) } }
          }
        }

        // ------------------------------------------------------- Ordinateur
        Column {
          visible: page.current === "computer"
          width: parent.width
          spacing: page.theme.spaceLarge
          ChoiceGroup {
            width: parent.width
            theme: page.theme
            title: page.tr("settings.defaultDifficulty")
            inline: true
            value: page.s.ai.difficulty
            options: Difficulty.DIFFICULTIES.map(function(d) { return { value: d, label: page.tr("difficulty." + d) } })
            onPicked: function(v) { page.set("ai.difficulty", v) }
          }
          ChoiceGroup {
            width: parent.width
            theme: page.theme
            title: page.tr("settings.thinking")
            inline: true
            value: page.s.ai.thinkingScale
            options: [{ value: 0.5, label: page.tr("settings.thinking.fast") }, { value: 1, label: page.tr("settings.thinking.normal") }, { value: 2, label: page.tr("settings.thinking.slow") }]
            onPicked: function(v) { page.set("ai.thinkingScale", v) }
          }
          ChoiceGroup {
            width: parent.width
            theme: page.theme
            title: page.tr("settings.personality")
            value: page.s.ai.personality
            options: [
              { value: "balanced", label: page.tr("personality.balanced"), detail: page.tr("settings.personality.balanced.detail") },
              { value: "aggressive", label: page.tr("personality.aggressive"), detail: page.tr("settings.personality.aggressive.detail") },
              { value: "cautious", label: page.tr("personality.cautious"), detail: page.tr("settings.personality.cautious.detail") }
            ]
            onPicked: function(v) { page.set("ai.personality", v) }
          }
        }

        // ------------------------------------------------------- Apparence
        Column {
          visible: page.current === "appearance"
          width: parent.width
          spacing: page.theme.spaceLarge
          ChoiceGroup {
            width: parent.width
            theme: page.theme
            title: page.tr("settings.appearance.colors")
            value: page.s.appearance
            options: [
              { value: "omarchy", label: page.tr("settings.appearance.omarchy"), detail: page.tr("settings.appearance.omarchy.detail") },
              { value: "light", label: page.tr("settings.appearance.light"), detail: page.tr("settings.appearance.light.detail") },
              { value: "dark", label: page.tr("settings.appearance.dark"), detail: page.tr("settings.appearance.dark.detail") },
              { value: "system", label: page.tr("settings.appearance.system"), detail: page.tr("settings.appearance.system.detail") }
            ]
            onPicked: function(v) { page.set("appearance", v) }
          }
          Column {
            width: parent.width
            spacing: page.theme.space
            ChoiceGroup {
              width: parent.width
              theme: page.theme
              title: page.tr("settings.animation")
              inline: true
              value: page.s.animation
              options: [
                { value: "auto", label: page.tr("settings.animation.auto") }, { value: "full", label: page.tr("settings.animation.full") },
                { value: "reduced", label: page.tr("settings.animation.reduced") }, { value: "off", label: page.tr("settings.animation.off") }
              ]
              onPicked: function(v) { page.set("animation", v) }
            }
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: page.tr("settings.animation.note")
              color: page.theme.muted
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontSmall
            }
          }
        }

        // ------------------------------------------------------- Langue
        Column {
          visible: page.current === "language"
          width: parent.width
          spacing: page.theme.spaceLarge
          ChoiceGroup {
            width: parent.width
            theme: page.theme
            title: page.tr("settings.language.interface")
            value: page.s.language
            options: [
              { value: "fr", label: page.tr("settings.language.fr") },
              { value: "en", label: page.tr("settings.language.en") },
              { value: "auto", label: page.tr("settings.language.auto"), detail: page.tr("settings.language.auto.detail") }
            ]
            onPicked: function(v) { page.set("language", v) }
          }
        }

        // ------------------------------------------------------- Accessibilité
        Column {
          visible: page.current === "accessibility"
          width: parent.width
          spacing: page.theme.spaceLarge
          SettingsCard {
            width: parent.width
            theme: page.theme
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.highContrast"); checked: page.s.accessibility.highContrast; onToggled: function(v) { page.set("accessibility.highContrast", v) } }
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.largerTiles"); checked: page.s.accessibility.largerTiles; onToggled: function(v) { page.set("accessibility.largerTiles", v) } }
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.largerText"); checked: page.s.accessibility.largerText; onToggled: function(v) { page.set("accessibility.largerText", v) } }
            ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.premiumLabels"); detail: page.tr("settings.premiumLabels.detail"); checked: page.s.accessibility.premiumLabels; onToggled: function(v) { page.set("accessibility.premiumLabels", v) } }
          }
        }

        // ------------------------------------------------------- Raccourcis
        Column {
          visible: page.current === "shortcuts"
          width: parent.width
          spacing: page.theme.spaceLarge
          SettingsCard {
            width: parent.width
            theme: page.theme
            Repeater {
              model: SettingsModel.SHORTCUT_ACTIONS
              Item {
                required property var modelData
                required property int index
                width: parent.width
                height: page.theme.controlHeight + 4
                Rectangle {
                  visible: index > 0
                  width: parent.width - 12
                  x: 6
                  height: 1
                  color: page.theme.line
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  x: 8
                  text: page.tr("shortcut." + modelData)
                  color: page.theme.foreground
                  font.family: page.theme.fontFamily
                  font.pixelSize: page.theme.fontBody
                }
                Row {
                  anchors.right: parent.right
                  anchors.rightMargin: 4
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: page.theme.space
                  KeyCap {
                    theme: page.theme
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.rebinding === modelData ? page.tr("settings.pressKey") : SettingsModel.shortcutLabel(page.s.shortcuts[modelData], page.tr)
                    color: page.rebinding === modelData ? page.theme.alpha(page.theme.accent, 0.18) : page.theme.panelStrong
                  }
                  GameButton { theme: page.theme; compact: true; variant: "ghost"; text: page.tr("common.edit"); onClicked: { page.rebinding = modelData; page.forceActiveFocus() } }
                }
              }
            }
          }
          GameButton { theme: page.theme; variant: "secondary"; text: page.tr("settings.resetShortcuts"); onClicked: page.set("shortcuts", SettingsModel.DEFAULT_SHORTCUTS) }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.tr("settings.shortcutsNote")
            color: page.theme.muted
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontSmall
          }
        }

        // ------------------------------------------------------- Définitions
        Column {
          visible: page.current === "definitions"
          width: parent.width
          spacing: page.theme.spaceLarge
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            color: page.theme.muted
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontSmall
            text: page.tr("settings.definitions.note")
          }
          Repeater {
            model: ["fr", "en"]
            SettingsCard {
              required property string modelData
              width: parent.width
              theme: page.theme
              title: page.tr("settings.definitions." + modelData)
              DefinitionsPack {
                x: 6
                width: parent.width - 12
                theme: page.theme
                definitions: page.definitions
                language: modelData
                allowRemove: true
                topPadding: 6
                bottomPadding: 6
              }
            }
          }
        }

        // ------------------------------------------------------- En ligne
        Column {
          visible: page.current === "online"
          width: parent.width
          spacing: page.theme.spaceLarge
          property string removing: ""
          Timer { id: removeTimeout; interval: 4000; onTriggered: parent.removing = "" }

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
              id: onlineName
              width: Math.min(320, parent.width)
              theme: page.theme
              placeholder: page.online ? page.online.systemUser : ""
              onEdited: function(t) { page.set("online.name", t.slice(0, 24)) }
              // Loaded when the page shows, not bound: see OnlineScreen.
              Connections {
                target: page
                function onCurrentChanged() { if (page.current === "online") onlineName.text = page.s.online.name }
                function onVisibleChanged() { if (page.visible && page.current === "online") onlineName.text = page.s.online.name }
              }
              Component.onCompleted: text = page.s.online.name
            }
            Text {
              text: page.tr("online.name.detail")
              color: page.theme.muted
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontCaption
            }
          }

          SettingsCard {
            width: parent.width
            theme: page.theme
            ToggleRow {
              width: parent.width
              theme: page.theme
              label: page.tr("settings.online.listen")
              detail: page.tr("settings.online.listen.detail")
              checked: page.s.online.listen
              onToggled: function(v) {
                page.set("online.listen", v)
                if (!page.online) return
                if (v) page.online.hello()
                else page.online.stop()
              }
            }
          }

          SettingsCard {
            id: friendsCard
            width: parent.width
            theme: page.theme
            title: page.tr("online.friends")
            readonly property string removing: parent.removing
            Text {
              visible: !page.online || page.online.friends.length === 0
              x: 10
              width: parent.width - 20
              topPadding: 8
              bottomPadding: 8
              wrapMode: Text.WordWrap
              text: page.online && page.online.checked && !page.online.available ? page.tr("settings.online.unavailable") : page.tr("settings.online.friends.empty")
              color: page.theme.muted
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontSmall
            }
            Repeater {
              model: page.online ? page.online.friends : []
              Item {
                required property var modelData
                required property int index
                width: parent.width
                height: page.theme.controlHeight + 8
                Rectangle { visible: index > 0; width: parent.width - 12; x: 6; height: 1; color: page.theme.line }
                Rectangle {
                  id: fdot
                  x: 10
                  anchors.verticalCenter: parent.verticalCenter
                  width: 8; height: 8; radius: 4
                  color: modelData.online ? page.theme.accent : page.theme.alpha(page.theme.foreground, 0.25)
                }
                Column {
                  anchors.left: fdot.right
                  anchors.leftMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  Text { text: modelData.name || "?"; color: page.theme.foreground; font.family: page.theme.fontFamily; font.pixelSize: page.theme.fontBody }
                  Text {
                    text: page.tr(modelData.online ? "online.friend.online" : "online.friend.offline")
                    color: page.theme.muted; font.family: page.theme.fontFamily; font.pixelSize: page.theme.fontCaption
                  }
                }
                GameButton {
                  anchors.right: parent.right
                  anchors.rightMargin: 4
                  anchors.verticalCenter: parent.verticalCenter
                  theme: page.theme
                  readonly property bool confirming: friendsCard.removing === modelData.id
                  variant: confirming ? "primary" : "ghost"
                  danger: confirming
                  text: page.tr(confirming ? "settings.online.removeConfirm" : "settings.online.remove")
                  onClicked: {
                    if (!confirming) { friendsCard.parent.removing = modelData.id; removeTimeout.restart(); return }
                    friendsCard.parent.removing = ""
                    page.online.forget(modelData.id)
                  }
                }
              }
            }
          }
        }

        // ------------------------------------------------------- À propos
        Column {
          id: aboutPage
          visible: page.current === "about"
          width: parent.width
          spacing: page.theme.spaceLarge
          readonly property var p: page.dictionary ? page.dictionary.provider : null
          SettingsCard {
            width: parent.width
            theme: page.theme
            title: page.tr("settings.about")
            Text {
              x: 8
              width: parent.width - 16
              topPadding: 6
              bottomPadding: 6
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              lineHeight: 1.2
              color: page.theme.foreground
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontBody
              readonly property var p: aboutPage.p
              text: p
                ? page.tr("settings.about.loaded", { name: page.tr("dict." + p.id() + ".label"), official: p.isOfficial() ? page.tr("settings.about.official") : "",
                                                   n: Format.formatInt(p.graph().wordCount, page.theme.language), version: p.version() })
                : page.tr("settings.about.notLoaded")
            }
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            color: page.theme.muted
            font.family: page.theme.fontFamily
            font.pixelSize: page.theme.fontSmall
            text: page.tr("settings.about.text")
          }
        }
      }
    }
  }
}
