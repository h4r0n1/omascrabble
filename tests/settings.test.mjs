import { normalizeSettings, withSetting, matchesShortcut, shortcutFromEvent, isValidShortcut, shortcutLabel, DEFAULT_SETTINGS } from "../app/settings.mjs"
import { formatInt, formatDecimal, cleanName, escapeMarkup } from "../app/format.mjs"

export const name = "Settings"

// Minimal stand-in for QML's Qt key constants.
const K = {
  ControlModifier: 0x04000000, ShiftModifier: 0x02000000, AltModifier: 0x08000000,
  Key_Return: 0x01000004, Key_Enter: 0x01000005, Key_Escape: 0x01000000, Key_Space: 0x20, Key_Tab: 0x01000001,
  Key_Backspace: 0x01000003, Key_Delete: 0x01000007, Key_Insert: 0x01000006, Key_Home: 0x01000010,
  Key_End: 0x01000011, Key_PageUp: 0x01000016, Key_PageDown: 0x01000017, Key_Slash: 0x2f, Key_Question: 0x3f,
  Key_F1: 0x01000030, Key_F12: 0x0100003b
}

export function register(t) {
  t.test("defaults survive a round trip", function() {
    t.deepEqual(normalizeSettings(JSON.parse(JSON.stringify(DEFAULT_SETTINGS))), normalizeSettings({}))
  })

  t.test("bad values fall back to defaults", function() {
    const s = normalizeSettings({ appearance: "neon", animation: 3, gameplay: { sounds: "yes" }, ai: { thinkingScale: 99, difficulty: "god" },
      newGame: { timeMinutes: 7, playerNames: ["  ", "Awa"], dictionary: "../etc/passwd" }, shortcuts: { pass: "Ctrl+Super+P", shuffle: "Ctrl+R" } })
    t.equal(s.appearance, "omarchy")
    t.equal(s.animation, "auto")
    t.equal(s.gameplay.sounds, false)
    t.equal(s.ai.thinkingScale, 3)
    t.equal(s.ai.difficulty, "casual")
    t.equal(s.newGame.timeMinutes, 20)
    t.deepEqual(s.newGame.playerNames, ["Joueur 1", "Awa"])
    t.equal(s.newGame.dictionary, "open-fr")
    t.equal(s.shortcuts.pass, "P")
    t.equal(s.shortcuts.shuffle, "Ctrl+R")
  })

  t.test("withSetting changes one path and normalizes", function() {
    const s = withSetting(normalizeSettings({}), "gameplay.sounds", true)
    t.equal(s.gameplay.sounds, true)
    t.equal(withSetting(s, "appearance", "bogus").appearance, "omarchy")
  })

  t.test("shortcut matching", function() {
    t.ok(matchesShortcut("Return", { key: K.Key_Enter, modifiers: 0 }, K))
    t.ok(matchesShortcut("P", { key: 0x50, modifiers: 0 }, K))
    t.ok(matchesShortcut("P", { key: 0x50, modifiers: K.ShiftModifier }, K), "letters ignore Shift")
    t.ok(!matchesShortcut("P", { key: 0x50, modifiers: K.ControlModifier }, K))
    t.ok(matchesShortcut("Ctrl+S", { key: 0x53, modifiers: K.ControlModifier }, K))
    t.ok(!matchesShortcut("Ctrl+S", { key: 0x53, modifiers: 0 }, K))
    t.ok(matchesShortcut("F1", { key: K.Key_F1, modifiers: 0 }, K))
    t.ok(!isValidShortcut("Super+Q"))
  })

  t.test("rebinding reads key events", function() {
    t.equal(shortcutFromEvent({ key: 0x53, modifiers: K.ControlModifier | K.ShiftModifier }, K), "Ctrl+Shift+S")
    t.equal(shortcutFromEvent({ key: K.Key_Escape, modifiers: 0 }, K), "Escape")
    t.equal(shortcutFromEvent({ key: 0x01001100, modifiers: 0 }, K), "")
    t.equal(shortcutLabel("Ctrl+Return"), "Ctrl + Enter")
    t.equal(shortcutLabel("Ctrl+Return", function(k) { return { "key.Return": "Entrée" }[k] }), "Ctrl + Entrée")
  })

  t.test("French number formatting", function() {
    t.equal(formatInt(407142), "407 142")
    t.equal(formatInt(-1234567), "−1 234 567")
    t.equal(formatDecimal(43.25, 1), "43,3")
  })

  t.test("English number formatting", function() {
    t.equal(formatInt(407142, "en"), "407,142")
    t.equal(formatInt(-1234567, "en"), "−1,234,567")
    t.equal(formatInt(999, "en"), "999")
    t.equal(formatDecimal(1234.25, 1, "en"), "1,234.3")
  })

  t.test("names from the other machine are cleaned", function() {
    t.equal(cleanName("  Ben\u0007 "), "Ben")
    t.equal(cleanName("Ana\u202Egnp.exe"), "Anagnp.exe", "no bidirectional override")
    t.equal(cleanName("x".repeat(60)).length, 40)
    t.equal(cleanName(null), "")
    t.equal(escapeMarkup("<b>Ben</b> & co"), "&lt;b&gt;Ben&lt;/b&gt; &amp; co")
  })
}
