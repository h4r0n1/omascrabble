import QtQuick
import "../app/format.mjs" as Format

// Install state of one language's definitions pack, with the actions that
// go with it: download (with progress and cancel), retry, remove. Used by
// the definitions dialog and by Settings; the download itself belongs to the
// DefinitionsService, so it carries on if this view goes away.
Column {
  id: pack

  property var theme
  property var definitions: null      // DefinitionsService
  property string language: "fr"      // pack language: fr | en
  property bool allowRemove: false
  property bool showCommand: false     // the terminal fallback

  readonly property var manifest: definitions && definitions.packs ? definitions.packs[language] || null : null
  readonly property bool checked: !!definitions && definitions.packsChecked[language] === true
  readonly property var job: definitions && definitions.job && definitions.job.language === language ? definitions.job : null
  readonly property bool active: !!job && !!definitions && definitions.busy
                                 && (job.stage === "preparing" || job.stage === "downloading" || job.stage === "writing")
  readonly property bool otherBusy: !!definitions && definitions.busy && !active
  readonly property real fraction: job && job.total > 0 ? Math.min(1, job.done / job.total) : 0
  property bool confirmingRemove: false

  function tr(key, args) { return theme.t(key, args) }
  function n(v) { return Format.formatInt(v, theme.language) }

  spacing: theme.space
  width: parent ? parent.width : 300

  Timer { id: confirmTimeout; interval: 4000; onTriggered: pack.confirmingRemove = false }

  // Installed.
  Row {
    visible: !!pack.manifest && !pack.active
    width: parent.width
    spacing: pack.theme.space
    Text {
      textFormat: Text.PlainText
      width: parent.width - (removeButton.visible ? removeButton.width + parent.spacing : 0)
      anchors.verticalCenter: parent.verticalCenter
      wrapMode: Text.WordWrap
      color: pack.theme.foreground
      font.family: pack.theme.fontFamily
      font.pixelSize: pack.theme.fontSmall
      text: !pack.manifest ? "" : pack.tr("defs.installed", {
        words: pack.n(pack.manifest.words || 0),
        date: pack.manifest.builtAt ? new Date(pack.manifest.builtAt).toLocaleDateString(Qt.locale(pack.theme.language === "en" ? "en_GB" : "fr_FR"), "d MMM yyyy") : "" })
    }
    GameButton {
      id: removeButton
      visible: pack.allowRemove
      theme: pack.theme
      variant: pack.confirmingRemove ? "primary" : "secondary"
      danger: pack.confirmingRemove
      enabled: !!pack.definitions && !pack.definitions.busy
      text: pack.tr(pack.confirmingRemove ? "defs.removeConfirm" : "defs.remove")
      onClicked: {
        if (!pack.confirmingRemove) { pack.confirmingRemove = true; confirmTimeout.restart(); return }
        pack.confirmingRemove = false
        pack.definitions.remove(pack.language)
      }
    }
  }

  // Downloading.
  Column {
    visible: pack.active
    width: parent.width
    spacing: pack.theme.space
    Rectangle {
      width: parent.width
      height: 6
      radius: 3
      color: pack.theme.alpha(pack.theme.foreground, 0.12)
      Rectangle {
        width: Math.max(height, parent.width * pack.fraction)
        height: parent.height
        radius: parent.radius
        color: pack.theme.accent
        Behavior on width { NumberAnimation { duration: pack.theme.anim(400) } }
      }
    }
    Row {
      width: parent.width
      spacing: pack.theme.space
      Text {
        textFormat: Text.PlainText
        width: parent.width - cancelButton.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.WordWrap
        color: pack.theme.muted
        font.family: pack.theme.fontFamily
        font.pixelSize: pack.theme.fontSmall
        text: !pack.job ? ""
          : pack.job.stage === "preparing" ? pack.tr("defs.preparing")
          : pack.job.stage === "writing" ? pack.tr("defs.writing", { kept: pack.n(pack.job.kept) })
          : pack.tr("defs.downloading", { percent: Math.floor(pack.fraction * 100), kept: pack.n(pack.job.kept) })
      }
      GameButton {
        id: cancelButton
        theme: pack.theme
        variant: "secondary"
        enabled: !!pack.job && pack.job.stage !== "writing"
        text: pack.tr("common.cancel")
        onClicked: pack.definitions.cancelInstall()
      }
    }
    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      color: pack.theme.muted
      font.family: pack.theme.fontFamily
      font.pixelSize: pack.theme.fontCaption
      text: pack.tr("defs.background")
    }
  }

  // Not installed.
  Column {
    visible: pack.checked && !pack.manifest && !pack.active
    width: parent.width
    spacing: pack.theme.space
    Row {
      spacing: pack.theme.space
      GameButton {
        id: downloadButton
        theme: pack.theme
        variant: "primary"
        icon: "download"
        enabled: !!pack.definitions && !pack.otherBusy && pack.definitions.pluginDir !== ""
        text: pack.tr(pack.job && (pack.job.stage === "error" || pack.job.stage === "cancelled") ? "defs.retry" : "defs.download",
                      { size: pack.tr(pack.language === "en" ? "words.size.en" : "words.size.fr") })
        onClicked: pack.definitions.install(pack.language)
      }
    }
    Text {
      textFormat: Text.PlainText
      visible: pack.otherBusy
      width: parent.width
      wrapMode: Text.WordWrap
      color: pack.theme.muted
      font.family: pack.theme.fontFamily
      font.pixelSize: pack.theme.fontSmall
      text: pack.tr("defs.busyOther")
    }
    Text {
      textFormat: Text.PlainText
      visible: !!pack.job && (pack.job.stage === "error" || pack.job.stage === "cancelled")
      width: parent.width
      wrapMode: Text.WordWrap
      color: pack.job && pack.job.stage === "error" ? pack.theme.urgent : pack.theme.muted
      font.family: pack.theme.fontFamily
      font.pixelSize: pack.theme.fontSmall
      text: !pack.job ? "" : pack.job.stage === "cancelled" ? pack.tr("defs.cancelled")
        : pack.tr("defs.error." + (pack.job.error ? pack.job.error.code : "other"))
    }
    Text {
      textFormat: Text.PlainText
      visible: !!pack.job && pack.job.stage === "error" && !!pack.job.error && pack.job.error.message !== ""
      width: parent.width
      wrapMode: Text.WrapAnywhere
      color: pack.theme.muted
      font.family: pack.theme.fontFamily
      font.pixelSize: pack.theme.fontCaption
      text: pack.job && pack.job.error ? pack.job.error.message : ""
    }
    Column {
      visible: pack.showCommand
      width: parent.width
      spacing: 4
      Text {
        textFormat: Text.PlainText
        color: pack.theme.muted
        font.family: pack.theme.fontFamily
        font.pixelSize: pack.theme.fontCaption
        text: pack.tr("defs.terminal")
      }
      TextEdit {
        textFormat: TextEdit.PlainText
        width: parent.width
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        text: "python3 ~/.config/omarchy/plugins/omascrabble/tools/download-definitions.py" + (pack.language === "en" ? " --lang en" : "")
        color: pack.theme.muted
        font.family: pack.theme.fontFamily
        font.pixelSize: pack.theme.fontCaption
      }
    }
  }
}
