import QtQuick
import QtQuick.Controls
import ".."
import "../../ai/difficulty.mjs" as Difficulty

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
  property string validation: "immediate"
  property string challengePenalty: "none"
  property string firstPlayer: "human"
  property string name1: "Joueur 1"
  property string name2: "Joueur 2"

  function reset() {
    var n = settings && settings.newGame ? settings.newGame : {}
    mode = n.mode || "human_vs_ai"
    difficulty = settings && settings.ai ? settings.ai.difficulty : "casual"
    timeMinutes = n.timeMinutes !== undefined ? n.timeMinutes : 20
    dictionaryId = n.dictionary || "open-fr"
    validation = n.validation || "immediate"
    challengePenalty = n.challengePenalty || "none"
    firstPlayer = n.firstPlayer || "human"
    name1 = n.playerNames ? n.playerNames[0] : "Joueur 1"
    name2 = n.playerNames ? n.playerNames[1] : "Joueur 2"
  }

  onVisibleChanged: if (visible) { reset(); Qt.callLater(function() { modeGroup.forceActiveFocus() }) }

  function start() {
    startRequested({
      mode: mode, difficulty: difficulty, timeMinutes: timeMinutes, dictionary: dictionaryId,
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
        GameButton { theme: setup.theme; icon: "back"; variant: "ghost"; focusable: false; tooltip: "Retour"; onClicked: setup.cancelled(); anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: "Nouvelle partie"
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
        title: "Mode"
        value: setup.mode
        options: [
          { value: "human_vs_ai", label: "Contre l’ordinateur", detail: "Une partie classique face à l’IA." },
          { value: "human_vs_human", label: "Deux joueurs locaux", detail: "Chacun son tour au même clavier ; le chevalet se masque entre les tours." },
          { value: "practice", label: "Entraînement", detail: "Seul, avec indices et le meilleur coup possible après chaque tour." }
        ]
        onPicked: function(v) { setup.mode = v }
      }

      ChoiceGroup {
        visible: setup.mode === "human_vs_ai"
        width: parent.width
        theme: setup.theme
        title: "Difficulté"
        value: setup.difficulty
        options: [
          { value: "beginner", label: Difficulty.DIFFICULTY_LABELS.beginner, detail: "Mots courants et courts, quelques maladresses." },
          { value: "casual", label: Difficulty.DIFFICULTY_LABELS.casual, detail: "Bons scores, vocabulaire moyen, sait viser les cases chères." },
          { value: "expert", label: Difficulty.DIFFICULTY_LABELS.expert, detail: "Tout le lexique, gestion du chevalet, se méfie des cases mot triple." },
          { value: "champion", label: Difficulty.DIFFICULTY_LABELS.champion, detail: "Anticipe les réponses possibles et calcule la fin de partie. Sans tricher." }
        ]
        onPicked: function(v) { setup.difficulty = v }
      }

      ChoiceGroup {
        width: parent.width
        theme: setup.theme
        title: "Temps par joueur"
        inline: true
        value: setup.timeMinutes
        options: [
          { value: 0, label: "Sans limite" }, { value: 10, label: "10 min" }, { value: 20, label: "20 min" },
          { value: 25, label: "25 min" }, { value: 30, label: "30 min" }
        ]
        onPicked: function(v) { setup.timeMinutes = v }
      }

      ChoiceGroup {
        width: parent.width
        theme: setup.theme
        title: "Dictionnaire"
        value: setup.dictionaryId
        options: setup.dictionary ? setup.dictionary.choices.map(function(d) {
          return { value: d.id, label: d.label, badge: d.badge, enabled: d.available, detail: d.available ? (d.official ? "" : d.note) : "Non installé — " + d.note }
        }) : []
        onPicked: function(v) { setup.dictionaryId = v }
      }

      ChoiceGroup {
        visible: setup.mode !== "practice"
        width: parent.width
        theme: setup.theme
        title: "Vérification des mots"
        value: setup.validation
        options: [
          { value: "immediate", label: "Immédiate", detail: "Un mot invalide est refusé dès que vous jouez." },
          { value: "challenge", label: "Contestation", detail: "Les coups sont joués sans vérification ; l’adversaire peut « Contester le coup »." }
        ]
        onPicked: function(v) { setup.validation = v }
      }

      ChoiceGroup {
        visible: setup.mode !== "practice" && setup.validation === "challenge"
        width: parent.width
        theme: setup.theme
        title: "Contestation refusée"
        inline: true
        value: setup.challengePenalty
        options: [
          { value: "none", label: "Sans pénalité" }, { value: "points", label: "−10 points" }, { value: "lose_turn", label: "Tour perdu" }
        ]
        onPicked: function(v) { setup.challengePenalty = v }
      }

      ChoiceGroup {
        visible: setup.mode !== "practice"
        width: parent.width
        theme: setup.theme
        title: "Qui commence"
        inline: true
        value: setup.firstPlayer
        options: setup.mode === "human_vs_ai"
          ? [{ value: "human", label: "Vous" }, { value: "ai", label: "L’ordinateur" }, { value: "random", label: "Au hasard" }]
          : [{ value: "human", label: setup.name1 }, { value: "random", label: "Au hasard" }]
        onPicked: function(v) { setup.firstPlayer = v }
      }

      Column {
        visible: setup.mode === "human_vs_human"
        width: parent.width
        spacing: setup.theme.space
        Text {
          text: "JOUEURS"
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
      GameButton { theme: setup.theme; text: "Annuler"; variant: "ghost"; onClicked: setup.cancelled() }
      GameButton {
        theme: setup.theme
        variant: "primary"
        text: setup.dictionary && setup.dictionary.status === "loading" ? "CHARGEMENT…" : "COMMENCER"
        enabled: !!setup.dictionary && setup.dictionary.status !== "loading"
        shortcutHint: "Ctrl + Entrée"
        onClicked: setup.start()
      }
    }
  }
}
