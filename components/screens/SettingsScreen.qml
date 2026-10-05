import QtQuick
import QtQuick.Controls
import ".."
import "../../app/format.mjs" as Format
import "../../app/settings.mjs" as SettingsModel
import "../../ai/difficulty.mjs" as Difficulty

// Réglages. Every change is saved immediately.
FocusScope {
  id: page

  property var theme
  property var saves
  property var dictionary
  property var definitions: null
  property string section: ""
  property string rebinding: ""          // shortcut being captured

  signal closed()

  readonly property var s: saves ? saves.settings : SettingsModel.normalizeSettings({})

  function tr(key, args) { return theme.t(key, args) }
  function set(path, value) { saves.saveSettings(SettingsModel.withSetting(s, path, value)) }

  onVisibleChanged: if (visible) {
    rebinding = ""
    Qt.callLater(function() {
      if (section === "about") flick.contentY = Math.max(0, about.y - page.theme.spaceHuge)
      else flick.contentY = 0
      section = ""
      firstControl.forceActiveFocus()
    })
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

  Flickable {
    id: flick
    anchors.fill: parent
    contentHeight: body.implicitHeight + 2 * page.theme.spaceHuge
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: body
      width: Math.min(680, parent.width - 2 * page.theme.padding)
      x: (parent.width - width) / 2
      y: page.theme.spaceHuge
      spacing: page.theme.spaceHuge

      Row {
        spacing: page.theme.space
        GameButton { theme: page.theme; icon: "back"; variant: "ghost"; focusable: false; tooltip: page.tr("common.back"); onClicked: page.closed(); anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: page.tr("settings.title")
          color: page.theme.foreground
          font.family: page.theme.fontFamily
          font.pixelSize: page.theme.fontDisplay
          font.weight: Font.Bold
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      SectionTitle { width: parent.width; theme: page.theme; text: page.tr("settings.language") }
      ChoiceGroup {
        id: firstControl
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

      SectionTitle { width: parent.width; theme: page.theme; text: page.tr("settings.appearance") }
      ChoiceGroup {
        width: parent.width
        theme: page.theme
        value: page.s.appearance
        options: [
          { value: "omarchy", label: page.tr("settings.appearance.omarchy"), detail: page.tr("settings.appearance.omarchy.detail") },
          { value: "light", label: page.tr("settings.appearance.light"), detail: page.tr("settings.appearance.light.detail") },
          { value: "dark", label: page.tr("settings.appearance.dark"), detail: page.tr("settings.appearance.dark.detail") },
          { value: "system", label: page.tr("settings.appearance.system"), detail: page.tr("settings.appearance.system.detail") }
        ]
        onPicked: function(v) { page.set("appearance", v) }
      }

      SectionTitle { width: parent.width; theme: page.theme; text: page.tr("settings.animation") }
      ChoiceGroup {
        width: parent.width
        theme: page.theme
        inline: true
        value: page.s.animation
        options: [
          { value: "auto", label: page.tr("settings.animation.auto") }, { value: "full", label: page.tr("settings.animation.full") },
          { value: "reduced", label: page.tr("settings.animation.reduced") }, { value: "off", label: page.tr("settings.animation.off") }
        ]
        onPicked: function(v) { page.set("animation", v) }
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: page.tr("settings.animation.note")
        color: page.theme.muted
        font.family: page.theme.fontFamily
        font.pixelSize: page.theme.fontSmall
      }

      SectionTitle { width: parent.width; theme: page.theme; text: page.tr("settings.gameplay") }
      Column {
        width: parent.width
        spacing: 2
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.confirmMoves"); detail: page.tr("settings.confirmMoves.detail"); checked: page.s.gameplay.confirmMoves; onToggled: function(v) { page.set("gameplay.confirmMoves", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.assisted"); detail: page.tr("settings.assisted.detail"); checked: page.s.gameplay.assistedPlacement; onToggled: function(v) { page.set("gameplay.assistedPlacement", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.scorePreview"); checked: page.s.gameplay.showScorePreview; onToggled: function(v) { page.set("gameplay.showScorePreview", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.wordValidation"); detail: page.tr("settings.wordValidation.detail"); checked: page.s.gameplay.showWordValidation; onToggled: function(v) { page.set("gameplay.showWordValidation", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.coordinates"); checked: page.s.gameplay.showCoordinates; onToggled: function(v) { page.set("gameplay.showCoordinates", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.sounds"); detail: page.tr("settings.sounds.detail"); checked: page.s.gameplay.sounds; onToggled: function(v) { page.set("gameplay.sounds", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.hideRack"); checked: page.s.gameplay.hideRackBetweenTurns; onToggled: function(v) { page.set("gameplay.hideRackBetweenTurns", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.pauseClock"); checked: page.s.gameplay.pauseClockWhenHidden; onToggled: function(v) { page.set("gameplay.pauseClockWhenHidden", v) } }
      }

      SectionTitle { width: parent.width; theme: page.theme; text: page.tr("settings.computer") }
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

      SectionTitle { width: parent.width; theme: page.theme; text: page.tr("settings.accessibility") }
      Column {
        width: parent.width
        spacing: 2
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.highContrast"); checked: page.s.accessibility.highContrast; onToggled: function(v) { page.set("accessibility.highContrast", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.largerTiles"); checked: page.s.accessibility.largerTiles; onToggled: function(v) { page.set("accessibility.largerTiles", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.largerText"); checked: page.s.accessibility.largerText; onToggled: function(v) { page.set("accessibility.largerText", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: page.tr("settings.premiumLabels"); detail: page.tr("settings.premiumLabels.detail"); checked: page.s.accessibility.premiumLabels; onToggled: function(v) { page.set("accessibility.premiumLabels", v) } }
      }

      SectionTitle { width: parent.width; theme: page.theme; text: page.tr("settings.shortcuts") }
      Column {
        width: parent.width
        spacing: 2
        Repeater {
          model: SettingsModel.SHORTCUT_ACTIONS
          Item {
            required property var modelData
            width: body.width
            height: page.theme.controlHeight + 4
            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: 6
              text: page.tr("shortcut." + modelData)
              color: page.theme.foreground
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontBody
            }
            Row {
              anchors.right: parent.right
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
        Row {
          spacing: page.theme.space
          GameButton { theme: page.theme; compact: true; variant: "ghost"; text: page.tr("settings.resetShortcuts"); onClicked: page.set("shortcuts", SettingsModel.DEFAULT_SHORTCUTS) }
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: page.tr("settings.shortcutsNote")
          color: page.theme.muted
          font.family: page.theme.fontFamily
          font.pixelSize: page.theme.fontSmall
        }
      }

      SectionTitle { width: parent.width; theme: page.theme; text: page.tr("settings.definitions") }
      Column {
        width: parent.width
        spacing: page.theme.spaceLarge
        Text {
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
          Column {
            required property string modelData
            width: parent.width
            spacing: page.theme.space
            Text {
              color: page.theme.foreground
              font.family: page.theme.fontFamily
              font.pixelSize: page.theme.fontBody
              font.weight: Font.DemiBold
              text: page.tr("settings.definitions." + modelData)
            }
            DefinitionsPack {
              width: parent.width
              theme: page.theme
              definitions: page.definitions
              language: modelData
              allowRemove: true
            }
          }
        }
      }

      SectionTitle { id: about; width: parent.width; theme: page.theme; text: page.tr("settings.about") }
      Column {
        width: parent.width
        spacing: page.theme.space
        readonly property var p: page.dictionary ? page.dictionary.provider : null
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          lineHeight: 1.2
          color: page.theme.foreground
          font.family: page.theme.fontFamily
          font.pixelSize: page.theme.fontBody
          text: parent.p
            ? page.tr("settings.about.loaded", { name: page.tr("dict." + parent.p.id() + ".label"), official: parent.p.isOfficial() ? page.tr("settings.about.official") : "",
                                               n: Format.formatInt(parent.p.graph().wordCount, page.theme.language), version: parent.p.version() })
            : page.tr("settings.about.notLoaded")
        }
        Text {
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
