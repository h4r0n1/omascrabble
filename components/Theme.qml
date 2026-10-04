import QtQuick
import qs.Commons

// The game's palette and metrics, derived from the active Omarchy theme.
//
// "omarchy" follows the shell's colours, radius and font directly. "light"
// and "dark" are warm built-in palettes for people who want the board to look
// the same whatever the desktop theme; they keep the Omarchy accent so the
// game still feels at home. "system" picks between those two from the
// freedesktop colour-scheme preference. Tiles are always warm ivory — the
// physical object — so letters read the same in every mode.
QtObject {
  id: theme

  property string appearance: "omarchy"
  property bool systemPrefersDark: true
  property string animation: "auto"
  property bool systemReducedMotion: false
  property bool highContrast: false
  property bool largerText: false
  property bool largerTiles: false
  property bool premiumLabels: true

  // Colour helpers accept colours or "#rrggbb" strings.
  function col(c) { return typeof c === "string" ? Qt.color(c) : c }
  function lum(c) { var x = col(c); return 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b }
  function mix(a, b, t) {
    var x = col(a), y = col(b)
    return Qt.rgba(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, x.a + (y.a - x.a) * t)
  }
  function alpha(c, a) { var x = col(c); return Qt.rgba(x.r, x.g, x.b, a) }
  function darkenTo(c, target) {
    var out = c
    for (var i = 0; i < 12 && lum(out) > target; i++) out = mix(out, "#000000", 0.18)
    return out
  }

  readonly property bool followOmarchy: appearance === "omarchy"
  readonly property bool dark: appearance === "dark" ? true
    : appearance === "light" ? false
    : appearance === "system" ? systemPrefersDark
    : lum(Color.background) < 0.5

  // ------------------------------------------------------------ base colours
  readonly property color background: highContrast ? (dark ? "#000000" : "#ffffff")
    : followOmarchy ? Color.background
    : dark ? "#1b1916" : "#f3efe6"
  readonly property color foreground: highContrast ? (dark ? "#ffffff" : "#000000")
    : followOmarchy ? Color.foreground
    : dark ? "#e9e3d7" : "#2a2622"
  readonly property color muted: highContrast ? foreground
    : followOmarchy ? mix(Color.foreground, Color.background, 0.42)
    : dark ? "#958c7e" : "#7b7368"
  readonly property color accent: highContrast ? (dark ? "#ffd75e" : "#0047b3") : Color.accent
  readonly property color urgent: highContrast ? (dark ? "#ff6b6b" : "#c00000") : Color.urgent
  readonly property color accentText: lum(accent) > 0.55 ? "#151515" : "#ffffff"

  readonly property color panel: mix(background, foreground, dark ? 0.05 : 0.04)
  readonly property color panelStrong: mix(background, foreground, dark ? 0.09 : 0.075)
  readonly property color line: alpha(foreground, highContrast ? 0.7 : 0.13)
  readonly property color lineStrong: alpha(foreground, highContrast ? 1 : 0.26)
  readonly property color focusRing: accent
  readonly property color scrim: alpha(dark ? "#000000" : "#1a1714", dark ? 0.55 : 0.32)

  // ------------------------------------------------------------- the board
  readonly property color warm: "#c89b5e"
  readonly property color boardFrame: highContrast ? foreground : mix(mix(background, foreground, dark ? 0.12 : 0.16), warm, 0.08)
  readonly property color cell: highContrast ? background : mix(mix(background, foreground, dark ? 0.06 : 0.035), warm, dark ? 0.05 : 0.07)
  readonly property color cellLabel: alpha(foreground, highContrast ? 1 : 0.5)

  // Classic premium hues, blended into the cell colour so they sit in the
  // theme instead of shouting over it.
  readonly property color hueTripleWord: "#c4573d"
  readonly property color hueDoubleWord: "#d6879a"
  readonly property color hueTripleLetter: "#3b74b4"
  readonly property color hueDoubleLetter: "#79b4d2"
  readonly property real premiumStrength: highContrast ? 0.95 : dark ? 0.5 : 0.58
  readonly property color tripleWord: mix(cell, hueTripleWord, premiumStrength)
  readonly property color doubleWord: mix(cell, hueDoubleWord, premiumStrength * 0.92)
  readonly property color tripleLetter: mix(cell, hueTripleLetter, premiumStrength)
  readonly property color doubleLetter: mix(cell, hueDoubleLetter, premiumStrength * 0.85)

  function premiumColor(type) {
    if (type === "TRIPLE_WORD") return tripleWord
    if (type === "DOUBLE_WORD" || type === "CENTER") return doubleWord
    if (type === "TRIPLE_LETTER") return tripleLetter
    if (type === "DOUBLE_LETTER") return doubleLetter
    return cell
  }
  function premiumInk(type) {
    if (type === "NONE") return cellLabel
    var c = premiumColor(type)
    return lum(c) > 0.5 ? alpha("#1c1813", 0.78) : alpha("#ffffff", 0.88)
  }
  // Colour-independent labels (French): Mot Triple, Mot Double, Lettre
  // Triple, Lettre Double, and the star.
  function premiumLabel(type) {
    if (type === "TRIPLE_WORD") return "MT"
    if (type === "DOUBLE_WORD") return "MD"
    if (type === "TRIPLE_LETTER") return "LT"
    if (type === "DOUBLE_LETTER") return "LD"
    if (type === "CENTER") return "★"
    return ""
  }
  function premiumName(type) {
    if (type === "TRIPLE_WORD") return "mot compte triple"
    if (type === "DOUBLE_WORD") return "mot compte double"
    if (type === "TRIPLE_LETTER") return "lettre compte triple"
    if (type === "DOUBLE_LETTER") return "lettre compte double"
    if (type === "CENTER") return "étoile centrale, mot compte double"
    return "case simple"
  }

  // ------------------------------------------------------------- the tiles
  readonly property color tileTop: highContrast ? "#ffffff" : dark ? "#ecdfc4" : "#f8efdc"
  readonly property color tileBottom: highContrast ? "#f0f0f0" : dark ? "#dccaa6" : "#ecdcbc"
  readonly property color tileEdge: highContrast ? "#000000" : dark ? "#9d8558" : "#bfa271"
  readonly property color tileShadow: alpha("#000000", dark ? 0.45 : 0.22)
  readonly property color tileInk: "#241c14"
  readonly property color tilePoints: alpha("#241c14", 0.72)
  readonly property color jokerInk: highContrast ? "#0047b3" : darkenTo(mix(accent, "#2c6f8e", 0.35), 0.18)
  readonly property color pendingRing: accent
  readonly property color lastMoveRing: alpha(accent, 0.55)
  readonly property color invalidRing: urgent

  // ----------------------------------------------------------- typography
  readonly property string fontFamily: Style.font.family
  readonly property real textScale: largerText ? 1.2 : 1
  function fontPx(px) { return Math.max(8, Math.round(px * textScale)) }
  readonly property int fontCaption: fontPx(Style.font.caption)
  readonly property int fontSmall: fontPx(Style.font.bodySmall)
  readonly property int fontBody: fontPx(Style.font.body)
  readonly property int fontSubtitle: fontPx(Style.font.subtitle)
  readonly property int fontTitle: fontPx(Style.font.title)
  readonly property int fontHeading: fontPx(Style.font.heading)
  readonly property int fontDisplay: fontPx(Style.font.display)
  readonly property int fontDisplayLarge: fontPx(Style.font.displayLarge)

  // -------------------------------------------------------------- metrics
  readonly property int radius: Style.cornerRadius
  readonly property int space: Style.spacing.md
  readonly property int spaceSmall: Style.spacing.sm
  readonly property int spaceLarge: Style.spacing.xl
  readonly property int spaceHuge: Style.spacing.huge
  readonly property int padding: Style.spacing.panelPadding
  readonly property int controlHeight: Math.round(Style.spacing.controlHeight * (largerText ? 1.15 : 1) * 1.15)
  readonly property int borderWidth: highContrast ? 2 : Math.max(1, Style.normalBorderWidth)
  readonly property real minCell: largerTiles ? 34 : 28
  function tileRadius(size) {
    return radius > 0 ? Math.min(size * 0.16, radius + 1) : Math.max(2, Math.round(size * 0.07))
  }

  // ------------------------------------------------------------ animation
  readonly property string motion: animation === "auto" ? (systemReducedMotion ? "reduced" : "full") : animation
  function anim(ms) {
    if (motion === "off") return 0
    if (motion === "reduced") return Math.round(ms * 0.35)
    return ms
  }
  readonly property bool motionEnabled: motion !== "off"
}
