// Scrabble position notation, per game language.
//
// French ("fr"): rows are lettered A–O from the top, columns numbered 1–15.
//   H4 = horizontal from row H, column 4; 4H = vertical from column 4, row H.
// English ("en"): columns are lettered A–O from the left, rows numbered 1–15.
//   8H = horizontal from row 8, column H; H8 = vertical from column H, row 8.
// In both, the row's label comes first for a horizontal word. In written
// records a joker/blank is shown in parentheses: MONTAG(E).

export const LETTERS = "ABCDEFGHIJKLMNO"
export const ROW_LABELS = LETTERS // French rows (kept for compatibility)

function style(s) { return s === "en" ? "en" : "fr" }

export function rowLabel(row, s) { return style(s) === "en" ? String(row + 1) : LETTERS.charAt(row) }
export function colLabel(col, s) { return style(s) === "en" ? LETTERS.charAt(col) : String(col + 1) }

export function cellLabel(row, col, s) {
  return style(s) === "en" ? colLabel(col, s) + rowLabel(row, s) : rowLabel(row, s) + colLabel(col, s)
}

export function positionLabel(direction, row, col, s) {
  return direction === "V" ? colLabel(col, s) + rowLabel(row, s) : rowLabel(row, s) + colLabel(col, s)
}

// `cells` carry { letter, isJoker }; jokers are written in parentheses.
export function wordNotation(cells) {
  let out = ""
  for (const c of cells) out += c.isJoker ? "(" + c.letter + ")" : c.letter
  return out
}

// Parses a position back to { direction, row, col }, or null.
export function parsePosition(label, s) {
  const text = String(label || "").trim().toUpperCase()
  const num = "(1[0-5]|[1-9])"
  let m
  if (style(s) === "en") {
    m = text.match(new RegExp("^" + num + "([A-O])$"))
    if (m) return { direction: "H", row: Number(m[1]) - 1, col: LETTERS.indexOf(m[2]) }
    m = text.match(new RegExp("^([A-O])" + num + "$"))
    if (m) return { direction: "V", row: Number(m[2]) - 1, col: LETTERS.indexOf(m[1]) }
    return null
  }
  m = text.match(new RegExp("^([A-O])" + num + "$"))
  if (m) return { direction: "H", row: LETTERS.indexOf(m[1]), col: Number(m[2]) - 1 }
  m = text.match(new RegExp("^" + num + "([A-O])$"))
  if (m) return { direction: "V", row: LETTERS.indexOf(m[2]), col: Number(m[1]) - 1 }
  return null
}
