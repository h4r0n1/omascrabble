// Everything the game shows is plain text: Qt's default text format guesses
// whether a string is HTML, and rich text can load images from the network.
// Downloaded definitions (and, online, the other player's name) must never
// be interpreted, so every Text and TextEdit says so explicitly.

export const name = "Plain text"

function matchBrace(src, i) {
  let depth = 0
  for (let j = i; j < src.length; j++) {
    const c = src[j]
    if (c === '"' || c === "'" || c === "`") {
      const q = c
      j++
      while (j < src.length && src[j] !== q) j += src[j] === "\\" ? 2 : 1
    } else if (src.startsWith("//", j)) {
      const k = src.indexOf("\n", j)
      j = k < 0 ? src.length : k
    } else if (src.startsWith("/*", j)) {
      j = src.indexOf("*/", j) + 1
    } else if (c === "{") {
      depth++
    } else if (c === "}") {
      depth--
      if (depth === 0) return j
    }
  }
  return -1
}

function directBody(src, start, end) {
  let out = ""
  for (let j = start; j < end; j++) {
    if (src[j] === "{") { j = matchBrace(src, j); out += "{}"; continue }
    out += src[j]
  }
  return out
}

export function register(t) {
  t.test("every Text and TextEdit is plain text", function(ctx) {
    if (!ctx.qmlSources) t.skip("QML sources not provided (Node runner only)")
    const open = new RegExp("(^|[^\\w.])(Text|TextEdit)\\s*\\{", "g")
    const missing = []
    let count = 0
    for (const path of Object.keys(ctx.qmlSources)) {
      const src = ctx.qmlSources[path]
      let m
      open.lastIndex = 0
      while ((m = open.exec(src)) !== null) {
        const brace = m.index + m[0].length - 1
        const close = matchBrace(src, brace)
        count++
        if (!/\btextFormat\s*:\s*(Text|TextEdit)\.PlainText\b/.test(directBody(src, brace + 1, close)))
          missing.push(path + ":" + (src.slice(0, brace).split("\n").length))
      }
    }
    t.ok(count > 50, "found the text elements (" + count + ")")
    t.deepEqual(missing, [])
  })
}
