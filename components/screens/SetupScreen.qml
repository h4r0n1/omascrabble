import QtQuick
import QtQuick.Controls
import ".."
import "../../ai/difficulty.mjs" as Difficulty
import "../../dictionary/registry.mjs" as Registry

// Nouvelle partie: mode, difficulty, time, dictionary and rules.
FocusScope {
  id: setup

  property var theme
  property var settings
  property var dictionary

  signal startRequested(var config)
  signal cancelled()

  // Working copy of the choices, seeded from the last game's settings.
  property string mode: "human_vs_ai"
  property string difficulty: "casual"
  property int timeMinutes: 20
  property string dictionaryId: "open-fr"
  property string gameLanguage: "fr"
  property string validation: "immediate"
  property string challengePenalty: "none"
  property string firstPlayer: "human"
  property string name1: ""
  property string name2: ""
  function tr(key, args) { return theme.t(key, args) }

  // The open dictionary of a language is the default; a licensed one is
  // kept if it was chosen before and is still installed.
  function dictionaryFor(language, preferred) {
    var choices = dictionary ? dictionary.choices : []
    for (var i = 0; i < choices.length; i++)
      if (choices[i].id === preferred && choices[i].language === language && choices[i].available) return preferred
    return language === "en" ? "open-en" : "open-fr"
  }

  function reset() {
    var n = settings && settings.newGame ? settings.newGame : {}
    mode = n.mode || "human_vs_ai"
    difficulty = settings && settings.ai ? settings.ai.difficulty : "casual"
    timeMinutes = n.timeMinutes !== undefined ? n.timeMinutes : 20
    gameLanguage = n.gameLanguage || "fr"
    dictionaryId = dictionaryFor(gameLanguage, n.dictionary)
    validation = n.validation || "immediate"
    challengePenalty = n.challengePenalty || "none"
    firstPlayer = n.firstPlayer || "human"
    var defaults = ["Joueur 1", "Joueur 2", ""]
    name1 = n.playerNames && defaults.indexOf(n.playerNames[0]) === -1 ? n.playerNames[0] : tr("player.defaultName", { n: 1 })
    name2 = n.playerNames && defaults.indexOf(n.playerNames[1]) === -1 ? n.playerNames[1] : tr("player.defaultName", { n: 2 })
  }

  onVisibleChanged: if (visible) { reset(); Qt.callLater(function() { modeGroup.forceActiveFocus() }) }

  function start() {
    startRequested({
      mode: mode, difficulty: difficulty, timeMinutes: timeMinutes, dictionary: dictionaryId, gameLanguage: gameLanguage,
      validation: mode === "practice" ? "immediate" : validation, challengePenalty: challengePenalty,
      firstPlayer: firstPlayer, playerNames: [name1, name2]
    })
  }

  Keys.onEscapePressed: cancelled()
  Keys.onPressed: function(event) {
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { start(); event.accepted = true }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.bottomMargin: footer.height
    contentHeight: form.implicitHeight + 2 * setup.theme.spaceHuge
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: form
      width: Math.min(620, flick.width - 2 * setup.theme.padding)
      x: (flick.width - width) / 2
      y: setup.theme.spaceHuge
      spacing: setup.theme.spaceHuge

      Row {
        spacing: setup.theme.space
        GameButton { theme: setup.theme; icon: "back"; variant: "ghost"; focusable: false; tooltip: setup.tr("common.back"); onClicked: setup.cancelled(); anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: setup.tr("setup.title")
          color: setup.theme.foreground
          font.family: setup.theme.fontFamily
          font.pixelSize: setup.theme.fontDisplay
          font.weight: Font.Bold
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      ChoiceGroup {
        id: modeGroup
        width: parent.width
        theme: setup.theme
        title: setup.tr("setup.mode")
        value: setup.mode
        options: ["human_vs_ai", "human_vs_human", "practice", "online"].map(function(m) {
          return { value: m, label: setup.tr("mode." + m), detail: setup.tr("setup.mode." + m + ".detail") }
        })
        onPicked: function(v) { setup.mode = v }
      }

      ChoiceGroup {
        width: parent.width
        theme: setup.theme
        title: setup.tr("setup.gameLanguage")
        inline: true
        value: setup.gameLanguage
        options: [{ value: "fr", label: setup.tr("setup.gameLanguage.fr") }, { value: "en", label: setup.tr("setup.gameLanguage.en") }]
        onPicked: function(v) { setup.gameLanguage = v; setup.dictionaryId = setup.dictionaryFor(v, setup.dictionaryId) }
      }

      ChoiceGroup {
        visible: setup.mode === "human_vs_ai"
        width: parent.width
        theme: setup.theme
        title: setup.tr("setup.difficulty")
        value: setup.difficulty
        options: Difficulty.DIFFICULTIES.map(function(d) {
          return { value: d, label: setup.tr("difficulty." + d), detail: setup.tr("setup.difficulty." + d + ".detail") }
        })
        onPicked: function(v) { setup.difficulty = v }
      }

      ChoiceGroup {
        width: parent.width
        theme: setup.theme
        title: setup.tr("setup.time")
        inline: true
        value: setup.timeMinutes
        options: [
          { value: 0, label: setup.tr("setup.time.none") }, { value: 10, label: setup.tr("common.minutes", { n: 10 }) },
          { value: 20, label: setup.tr("common.minutes", { n: 20 }) }, { value: 25, label: setup.tr("common.minutes", { n: 25 }) },
          { value: 30, label: setup.tr("common.minutes", { n: 30 }) }
        ]
        onPicked: function(v) { setup.timeMinutes = v }
      }

      ChoiceGroup {
        width: parent.width
        theme: setup.theme
        title: setup.tr("setup.dictionary")
        value: setup.dictionaryId
        options: setup.dictionary ? setup.dictionary.choices.filter(function(d) { return d.language === setup.gameLanguage }).map(function(d) {
          var note = setup.tr("dict." + d.id + ".note")
          return { value: d.id, label: setup.tr("dict." + d.id + ".label"), badge: d.official ? setup.tr("dict.official") : "", enabled: d.available,
                   detail: d.available ? (d.official ? "" : note) : setup.tr("dict.notInstalled", { note: note }) }
        }) : []
        onPicked: function(v) { setup.dictionaryId = v }
      }

      ChoiceGroup {
        visible: setup.mode !== "practice"
        width: parent.width
        theme: setup.theme
        title: setup.tr("setup.validation")
        value: setup.validation
        options: ["immediate", "challenge"].map(function(v) {
          return { value: v, label: setup.tr("setup.validation." + v), detail: setup.tr("setup.validation." + v + ".detail") }
        })
        onPicked: function(v) { setup.validation = v }
      }

      ChoiceGroup {
        visible: setup.mode !== "practice" && setup.validation === "challenge"
        width: parent.width
        theme: setup.theme
        title: setup.tr("setup.penalty")
        inline: true
        value: setup.challengePenalty
        options: [
          { value: "none", label: setup.tr("setup.penalty.none") }, { value: "points", label: setup.tr("setup.penalty.points") },
          { value: "lose_turn", label: setup.tr("setup.penalty.lose_turn") }
        ]
        onPicked: function(v) { setup.challengePenalty = v }
      }

      ChoiceGroup {
        visible: setup.mode !== "practice" && setup.mode !== "online"
        width: parent.width
        theme: setup.theme
        title: setup.tr("setup.first")
        inline: true
        value: setup.firstPlayer
        options: setup.mode === "human_vs_ai"
          ? [{ value: "human", label: setup.tr("setup.first.human") }, { value: "ai", label: setup.tr("setup.first.ai") }, { value: "random", label: setup.tr("setup.first.random") }]
          : [{ value: "human", label: setup.name1 }, { value: "random", label: setup.tr("setup.first.random") }]
        onPicked: function(v) { setup.firstPlayer = v }
      }

      Column {
        visible: setup.mode === "human_vs_human"
        width: parent.width
        spacing: setup.theme.space
        Text {
          text: setup.tr("setup.players")
          color: setup.theme.muted
          font.family: setup.theme.fontFamily
          font.pixelSize: setup.theme.fontCaption
          font.weight: Font.Bold
          font.letterSpacing: 1.2
        }
        Row {
          spacing: setup.theme.space
          NameField { theme: setup.theme; width: (form.width - setup.theme.space) / 2; text: setup.name1; onEdited: function(t) { setup.name1 = t } }
          NameField { theme: setup.theme; width: (form.width - setup.theme.space) / 2; text: setup.name2; onEdited: function(t) { setup.name2 = t } }
        }
      }
    }
  }

  Rectangle {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: setup.theme.controlHeight + 2 * setup.theme.padding
    color: setup.theme.background
    Rectangle { width: parent.width; height: 1; color: setup.theme.line }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: Math.max(setup.theme.padding, (parent.width - form.width) / 2)
      anchors.verticalCenter: parent.verticalCenter
      spacing: setup.theme.space
      GameButton { theme: setup.theme; text: setup.tr("common.cancel"); variant: "ghost"; onClicked: setup.cancelled() }
      GameButton {
        theme: setup.theme
        variant: "primary"
        text: setup.tr(setup.mode === "online" ? "setup.invite" : setup.dictionary && setup.dictionary.status === "loading" ? "setup.loading" : "setup.start")
        enabled: !!setup.dictionary && setup.dictionary.status !== "loading"
        shortcutHint: setup.tr("setup.startShortcut")
        onClicked: setup.start()
      }
    }
  }
}
