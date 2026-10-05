// Settings: defaults, and normalization of whatever is read from disk.
// Unknown keys are dropped and bad values fall back to defaults, so a
// hand-edited or older settings file can never put the game in a strange
// state.

export const SETTINGS_VERSION = 1

export const DEFAULT_SHORTCUTS = Object.freeze({
  confirm: "Return",
  cancel: "Escape",
  select: "Space",
  shuffle: "R",
  pass: "P",
  exchange: "E",
  challenge: "C",
  newGame: "N",
  save: "Ctrl+S",
  hint: "H",
  history: "Y",
  help: "F1"
})

// Labels live in the interface catalogs as "shortcut.<action>".
export const SHORTCUT_ACTIONS = Object.freeze(Object.keys(DEFAULT_SHORTCUTS))

export const DEFAULT_SETTINGS = Object.freeze({
  version: SETTINGS_VERSION,
  language: "en",            // en | fr | auto (system locale) — interface only
  appearance: "omarchy",      // omarchy | light | dark | system
  animation: "auto",          // auto | full | reduced | off
  gameplay: Object.freeze({
    confirmMoves: false,
    assistedPlacement: true,  // typing letters on the board places tiles
    showScorePreview: true,
    showWordValidation: true,
    showCoordinates: true,
    sounds: false,
    hideRackBetweenTurns: true,
    pauseClockWhenHidden: true
  }),
  ai: Object.freeze({
    difficulty: "casual",
    thinkingScale: 1,
    personality: "balanced"
  }),
  accessibility: Object.freeze({
    highContrast: false,
    largerTiles: false,
    largerText: false,
    premiumLabels: true
  }),
  newGame: Object.freeze({
    mode: "human_vs_ai",
    timeMinutes: 20,
    dictionary: "open-fr",
    gameLanguage: "fr",
    validation: "immediate",
    challengePenalty: "none",
    firstPlayer: "human",
    playerNames: Object.freeze(["Joueur 1", "Joueur 2"])
  }),
  shortcuts: DEFAULT_SHORTCUTS,
  online: Object.freeze({
    name: "",                 // shown to the other player; "" = the system user name
    listen: true,             // friends may invite me while the game is loaded
    knownFriends: false       // set once a friend exists: go online at startup to hear their calls
  })
})

const ENUMS = {
  language: ["fr", "en", "auto"],
  appearance: ["omarchy", "light", "dark", "system"],
  animation: ["auto", "full", "reduced", "off"],
  difficulty: ["beginner", "casual", "expert", "champion"],
  personality: ["balanced", "aggressive", "cautious"],
  mode: ["human_vs_ai", "human_vs_human", "practice", "online"],
  validation: ["immediate", "challenge"],
  challengePenalty: ["none", "points", "lose_turn"],
  firstPlayer: ["human", "ai", "random"]
}

export const TIME_CHOICES = Object.freeze([0, 10, 20, 25, 30])

function pick(value, allowed, fallback) {
  return allowed.indexOf(value) !== -1 ? value : fallback
}

function bool(value, fallback) {
  return typeof value === "boolean" ? value : fallback
}

function obj(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {}
}

// A shortcut is "Key" or "Mod+…+Key" with Ctrl/Shift/Alt modifiers.
export function isValidShortcut(text) {
  if (typeof text !== "string" || text.length === 0 || text.length > 32) return false
  const parts = text.split("+")
  const key = parts.pop()
  if (!key) return false
  for (const m of parts) if (["Ctrl", "Shift", "Alt"].indexOf(m) === -1) return false
  return /^([A-Z0-9]|F[1-9]|F1[0-2]|Return|Escape|Space|Tab|Backspace|Delete|Insert|Home|End|PageUp|PageDown|Slash|Question)$/.test(key)
}

export function normalizeSettings(input) {
  const src = obj(input)
  const d = DEFAULT_SETTINGS
  const g = obj(src.gameplay), ai = obj(src.ai), a = obj(src.accessibility), n = obj(src.newGame), sc = obj(src.shortcuts)
  const names = Array.isArray(n.playerNames) ? n.playerNames : []
  const shortcuts = {}
  for (const k in DEFAULT_SHORTCUTS) shortcuts[k] = isValidShortcut(sc[k]) ? sc[k] : DEFAULT_SHORTCUTS[k]
  const scale = Number(ai.thinkingScale)
  return {
    version: SETTINGS_VERSION,
    language: pick(src.language, ENUMS.language, d.language),
    appearance: pick(src.appearance, ENUMS.appearance, d.appearance),
    animation: pick(src.animation, ENUMS.animation, d.animation),
    gameplay: {
      confirmMoves: bool(g.confirmMoves, d.gameplay.confirmMoves),
      assistedPlacement: bool(g.assistedPlacement, d.gameplay.assistedPlacement),
      showScorePreview: bool(g.showScorePreview, d.gameplay.showScorePreview),
      showWordValidation: bool(g.showWordValidation, d.gameplay.showWordValidation),
      showCoordinates: bool(g.showCoordinates, d.gameplay.showCoordinates),
      sounds: bool(g.sounds, d.gameplay.sounds),
      hideRackBetweenTurns: bool(g.hideRackBetweenTurns, d.gameplay.hideRackBetweenTurns),
      pauseClockWhenHidden: bool(g.pauseClockWhenHidden, d.gameplay.pauseClockWhenHidden)
    },
    ai: {
      difficulty: pick(ai.difficulty, ENUMS.difficulty, d.ai.difficulty),
      thinkingScale: Number.isFinite(scale) ? Math.max(0.25, Math.min(3, scale)) : d.ai.thinkingScale,
      personality: pick(ai.personality, ENUMS.personality, d.ai.personality)
    },
    accessibility: {
      highContrast: bool(a.highContrast, d.accessibility.highContrast),
      largerTiles: bool(a.largerTiles, d.accessibility.largerTiles),
      largerText: bool(a.largerText, d.accessibility.largerText),
      premiumLabels: bool(a.premiumLabels, d.accessibility.premiumLabels)
    },
    newGame: {
      mode: pick(n.mode, ENUMS.mode, d.newGame.mode),
      timeMinutes: TIME_CHOICES.indexOf(n.timeMinutes) !== -1 ? n.timeMinutes : d.newGame.timeMinutes,
      dictionary: typeof n.dictionary === "string" && /^[a-z0-9-]{1,32}$/.test(n.dictionary) ? n.dictionary : d.newGame.dictionary,
      gameLanguage: pick(n.gameLanguage, ["fr", "en"], d.newGame.gameLanguage),
      validation: pick(n.validation, ENUMS.validation, d.newGame.validation),
      challengePenalty: pick(n.challengePenalty, ENUMS.challengePenalty, d.newGame.challengePenalty),
      firstPlayer: pick(n.firstPlayer, ENUMS.firstPlayer, d.newGame.firstPlayer),
      playerNames: [0, 1].map(function(i) {
        const v = names[i]
        return typeof v === "string" && v.trim().length > 0 ? v.trim().slice(0, 24) : d.newGame.playerNames[i]
      })
    },
    shortcuts: shortcuts,
    online: {
      // Not trimmed here: this runs on every keystroke of the name field,
      // and trimming would swallow a space as it's typed. Users trim it.
      name: typeof obj(src.online).name === "string" ? obj(src.online).name.replace(/^\s+/, "").slice(0, 24) : "",
      listen: bool(obj(src.online).listen, d.online.listen),
      knownFriends: bool(obj(src.online).knownFriends, d.online.knownFriends)
    }
  }
}

// Returns a copy of `settings` with `path` ("gameplay.sounds") set to value,
// normalized.
export function withSetting(settings, path, value) {
  const copy = JSON.parse(JSON.stringify(settings))
  const parts = String(path).split(".")
  let target = copy
  for (let i = 0; i < parts.length - 1; i++) {
    if (!target[parts[i]] || typeof target[parts[i]] !== "object") target[parts[i]] = {}
    target = target[parts[i]]
  }
  target[parts[parts.length - 1]] = value
  return normalizeSettings(copy)
}

// Matches a key event against a shortcut string. `event` carries { key,
// modifiers, text } as QML gives them; `Qt` constants are passed in so this
// module stays free of QML globals.
export function matchesShortcut(shortcut, event, keys) {
  if (!isValidShortcut(shortcut)) return false
  const parts = shortcut.split("+")
  const key = parts.pop()
  const want = { Ctrl: false, Shift: false, Alt: false }
  for (const m of parts) want[m] = true
  const has = {
    Ctrl: (event.modifiers & keys.ControlModifier) !== 0,
    Shift: (event.modifiers & keys.ShiftModifier) !== 0,
    Alt: (event.modifiers & keys.AltModifier) !== 0
  }
  // Shift is ignored for letters typed as uppercase unless asked for.
  if (want.Ctrl !== has.Ctrl || want.Alt !== has.Alt) return false
  if (want.Shift && !has.Shift) return false
  if (!want.Shift && has.Shift && key.length !== 1) return false
  const named = {
    Return: [keys.Key_Return, keys.Key_Enter], Escape: [keys.Key_Escape], Space: [keys.Key_Space], Tab: [keys.Key_Tab],
    Backspace: [keys.Key_Backspace], Delete: [keys.Key_Delete], Insert: [keys.Key_Insert], Home: [keys.Key_Home],
    End: [keys.Key_End], PageUp: [keys.Key_PageUp], PageDown: [keys.Key_PageDown], Slash: [keys.Key_Slash],
    Question: [keys.Key_Question]
  }
  if (named[key]) return named[key].indexOf(event.key) !== -1
  const f = key.match(/^F(\d+)$/)
  if (f) return event.key === keys.Key_F1 + Number(f[1]) - 1
  if (key.length === 1) {
    const code = key.charCodeAt(0)
    return event.key === code
  }
  return false
}

// Describes a key event as a shortcut string (for the rebinding UI), or "".
export function shortcutFromEvent(event, keys) {
  const mods = []
  if (event.modifiers & keys.ControlModifier) mods.push("Ctrl")
  if (event.modifiers & keys.ShiftModifier) mods.push("Shift")
  if (event.modifiers & keys.AltModifier) mods.push("Alt")
  let key = ""
  const named = [[keys.Key_Return, "Return"], [keys.Key_Enter, "Return"], [keys.Key_Escape, "Escape"], [keys.Key_Space, "Space"],
    [keys.Key_Tab, "Tab"], [keys.Key_Backspace, "Backspace"], [keys.Key_Delete, "Delete"], [keys.Key_Insert, "Insert"],
    [keys.Key_Home, "Home"], [keys.Key_End, "End"], [keys.Key_PageUp, "PageUp"], [keys.Key_PageDown, "PageDown"],
    [keys.Key_Slash, "Slash"], [keys.Key_Question, "Question"]]
  for (const pair of named) if (event.key === pair[0]) key = pair[1]
  if (!key && event.key >= keys.Key_F1 && event.key <= keys.Key_F12) key = "F" + (event.key - keys.Key_F1 + 1)
  if (!key && event.key >= 0x41 && event.key <= 0x5a) key = String.fromCharCode(event.key)
  if (!key && event.key >= 0x30 && event.key <= 0x39) key = String.fromCharCode(event.key)
  if (!key) return ""
  const text = mods.concat([key]).join("+")
  return isValidShortcut(text) ? text : ""
}

// `tr(key)` translates key names (key.Return…); defaults to French.
export function shortcutLabel(shortcut, tr) {
  const named = { Return: "Enter", Escape: "Esc", Space: "Space", Backspace: "Backspace", Delete: "Del", Shift: "Shift" }
  const fixed = { Ctrl: "Ctrl", Alt: "Alt", Slash: "/", Question: "?" }
  return String(shortcut || "").split("+").map(function(p) {
    if (fixed[p]) return fixed[p]
    if (named[p]) return tr ? tr("key." + p) : named[p]
    return p
  }).join(" + ")
}
