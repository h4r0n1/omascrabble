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
  property string section: ""
  property string rebinding: ""          // shortcut being captured

  signal closed()

  readonly property var s: saves ? saves.settings : SettingsModel.normalizeSettings({})

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
        GameButton { theme: page.theme; icon: "back"; variant: "ghost"; focusable: false; tooltip: "Retour"; onClicked: page.closed(); anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: "Réglages"
          color: page.theme.foreground
          font.family: page.theme.fontFamily
          font.pixelSize: page.theme.fontDisplay
          font.weight: Font.Bold
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      SectionTitle { width: parent.width; theme: page.theme; text: "Apparence" }
      ChoiceGroup {
        id: firstControl
        width: parent.width
        theme: page.theme
        value: page.s.appearance
        options: [
          { value: "omarchy", label: "Suivre le thème Omarchy", detail: "Couleurs, police et arrondis du thème actif." },
          { value: "light", label: "Clair", detail: "Palette chaude et claire, quel que soit le thème." },
          { value: "dark", label: "Sombre", detail: "Palette chaude et sombre, quel que soit le thème." },
          { value: "system", label: "Système", detail: "Clair ou sombre selon la préférence du bureau." }
        ]
        onPicked: function(v) { page.set("appearance", v) }
      }

      SectionTitle { width: parent.width; theme: page.theme; text: "Animations" }
      ChoiceGroup {
        width: parent.width
        theme: page.theme
        inline: true
        value: page.s.animation
        options: [
          { value: "auto", label: "Automatique" }, { value: "full", label: "Complètes" },
          { value: "reduced", label: "Réduites" }, { value: "off", label: "Désactivées" }
        ]
        onPicked: function(v) { page.set("animation", v) }
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "« Automatique » réduit les animations quand le bureau demande moins de mouvement (préférence « enable-animations »)."
        color: page.theme.muted
        font.family: page.theme.fontFamily
        font.pixelSize: page.theme.fontSmall
      }

      SectionTitle { width: parent.width; theme: page.theme; text: "Jeu" }
      Column {
        width: parent.width
        spacing: 2
        ToggleRow { width: parent.width; theme: page.theme; label: "Confirmer avant de jouer"; detail: "Affiche le récapitulatif du coup avant de le valider."; checked: page.s.gameplay.confirmMoves; onToggled: function(v) { page.set("gameplay.confirmMoves", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: "Placement assisté"; detail: "Sur le plateau, taper une lettre pose le jeton et avance ; le joker est utilisé si la lettre manque."; checked: page.s.gameplay.assistedPlacement; onToggled: function(v) { page.set("gameplay.assistedPlacement", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: "Aperçu du score"; checked: page.s.gameplay.showScorePreview; onToggled: function(v) { page.set("gameplay.showScorePreview", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: "Signaler les mots invalides"; detail: "Pendant que vous posez vos lettres (jamais en mode contestation)."; checked: page.s.gameplay.showWordValidation; onToggled: function(v) { page.set("gameplay.showWordValidation", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: "Coordonnées du plateau"; checked: page.s.gameplay.showCoordinates; onToggled: function(v) { page.set("gameplay.showCoordinates", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: "Sons"; detail: "Discrets ; désactivés par défaut."; checked: page.s.gameplay.sounds; onToggled: function(v) { page.set("gameplay.sounds", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: "Masquer le chevalet entre deux joueurs"; checked: page.s.gameplay.hideRackBetweenTurns; onToggled: function(v) { page.set("gameplay.hideRackBetweenTurns", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: "Arrêter la pendule quand la fenêtre est masquée"; checked: page.s.gameplay.pauseClockWhenHidden; onToggled: function(v) { page.set("gameplay.pauseClockWhenHidden", v) } }
      }

      SectionTitle { width: parent.width; theme: page.theme; text: "Ordinateur" }
      ChoiceGroup {
        width: parent.width
        theme: page.theme
        title: "Difficulté par défaut"
        inline: true
        value: page.s.ai.difficulty
        options: Difficulty.DIFFICULTIES.map(function(d) { return { value: d, label: Difficulty.DIFFICULTY_LABELS[d] } })
        onPicked: function(v) { page.set("ai.difficulty", v) }
      }
      ChoiceGroup {
        width: parent.width
        theme: page.theme
        title: "Temps de réflexion"
        inline: true
        value: page.s.ai.thinkingScale
        options: [{ value: 0.5, label: "Rapide" }, { value: 1, label: "Normal" }, { value: 2, label: "Posé" }]
        onPicked: function(v) { page.set("ai.thinkingScale", v) }
      }
      ChoiceGroup {
        width: parent.width
        theme: page.theme
        title: "Personnalité"
        value: page.s.ai.personality
        options: [
          { value: "balanced", label: Difficulty.PERSONALITIES.balanced.label, detail: "Score, chevalet et défense en équilibre." },
          { value: "aggressive", label: Difficulty.PERSONALITIES.aggressive.label, detail: "Vise les gros coups et les cases chères, ouvre volontiers le jeu." },
          { value: "cautious", label: Difficulty.PERSONALITIES.cautious.label, detail: "Ferme les cases mot triple et soigne son chevalet." }
        ]
        onPicked: function(v) { page.set("ai.personality", v) }
      }

      SectionTitle { width: parent.width; theme: page.theme; text: "Accessibilité" }
      Column {
        width: parent.width
        spacing: 2
        ToggleRow { width: parent.width; theme: page.theme; label: "Contraste élevé"; checked: page.s.accessibility.highContrast; onToggled: function(v) { page.set("accessibility.highContrast", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: "Jetons plus grands"; checked: page.s.accessibility.largerTiles; onToggled: function(v) { page.set("accessibility.largerTiles", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: "Texte plus grand"; checked: page.s.accessibility.largerText; onToggled: function(v) { page.set("accessibility.largerText", v) } }
        ToggleRow { width: parent.width; theme: page.theme; label: "Cases spéciales lisibles sans couleur"; detail: "Affiche MT, MD, LT, LD et ★ sur les cases."; checked: page.s.accessibility.premiumLabels; onToggled: function(v) { page.set("accessibility.premiumLabels", v) } }
      }

      SectionTitle { width: parent.width; theme: page.theme; text: "Raccourcis clavier" }
      Column {
        width: parent.width
        spacing: 2
        Repeater {
          model: Object.keys(SettingsModel.SHORTCUT_LABELS)
          Item {
            required property var modelData
            width: body.width
            height: page.theme.controlHeight + 4
            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: 6
              text: SettingsModel.SHORTCUT_LABELS[modelData]
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
                text: page.rebinding === modelData ? "Appuyez sur une touche…" : SettingsModel.shortcutLabel(page.s.shortcuts[modelData])
                color: page.rebinding === modelData ? page.theme.alpha(page.theme.accent, 0.18) : page.theme.panelStrong
              }
              GameButton { theme: page.theme; compact: true; variant: "ghost"; text: "Modifier"; onClicked: { page.rebinding = modelData; page.forceActiveFocus() } }
            }
          }
        }
        Row {
          spacing: page.theme.space
          GameButton { theme: page.theme; compact: true; variant: "ghost"; text: "Rétablir les raccourcis par défaut"; onClicked: page.set("shortcuts", SettingsModel.DEFAULT_SHORTCUTS) }
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Les raccourcis d’Omarchy et d’Hyprland (touche Super) restent prioritaires : le jeu ne reçoit que les touches de sa fenêtre."
          color: page.theme.muted
          font.family: page.theme.fontFamily
          font.pixelSize: page.theme.fontSmall
        }
      }

      SectionTitle { id: about; width: parent.width; theme: page.theme; text: "Dictionnaire et licences" }
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
            ? parent.p.name() + (parent.p.isOfficial() ? " — officiel" : "") + "\n"
              + Format.formatInt(parent.p.graph().wordCount) + " mots jouables · version " + parent.p.version()
            : "Dictionnaire non chargé."
        }
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          lineHeight: 1.2
          color: page.theme.muted
          font.family: page.theme.fontFamily
          font.pixelSize: page.theme.fontSmall
          text: "Le lexique ouvert est dérivé du « Lexique des formes fléchies du français » de Grammalecte (Olivier R., Dicollecte), version 7.7, publié sous licence Mozilla Public License 2.0. Il n’est pas l’Officiel du Scrabble (ODS) : certains mots acceptés par l’ODS en sont absents, et inversement. "
            + "Les accents et les ligatures (é, ç, œ…) se jouent sans accent ; une entrée contenant tout autre caractère (tiret, apostrophe, ñ…) est écartée, jamais tronquée.\n\n"
            + "L’ODS 9, référence officielle 2024–2027, est sous licence et n’est pas fourni. Avec une licence, sa liste peut être compilée par tools/build-dictionary.mjs dans ~/.local/share/omarchy-scrabble/dictionaries/ods9.dawg ; il apparaîtra alors dans « Nouvelle partie ».\n\n"
            + "Jeu : licence MIT. Projet communautaire indépendant ; SCRABBLE® est une marque de ses propriétaires respectifs, sans lien avec ce projet."
        }
      }
    }
  }
}
