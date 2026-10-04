// French Scrabble notation.
//
// Rows are lettered A–O from the top, columns numbered 1–15 from the left.
// A position starting with a letter is a horizontal word (H4 = row H from
// column 4); one starting with a number is vertical (4H = column 4 from
// row H). In written records a joker is shown in parentheses: MONTAG(E).

export const ROW_LABELS = "ABCDEFGHIJKLMNO"

export function rowLabel(row) { return ROW_LABELS.charAt(row) }
export function colLabel(col) { return String(col + 1) }

export function cellLabel(row, col) {
  return rowLabel(row) + colLabel(col)
}

export function positionLabel(direction, row, col) {
  return direction === "V" ? colLabel(col) + rowLabel(row) : rowLabel(row) + colLabel(col)
}

// `cells` carry { letter, isJoker }; jokers are written in parentheses.
export function wordNotation(cells) {
  let s = ""
  for (const c of cells) s += c.isJoker ? "(" + c.letter + ")" : c.letter
  return s
}

// Parses "H8"/"8H" back to { direction, row, col }, or null.
export function parsePosition(label) {
  const s = String(label || "").trim().toUpperCase()
  let m = s.match(/^([A-O])(1[0-5]|[1-9])$/)
  if (m) return { direction: "H", row: ROW_LABELS.indexOf(m[1]), col: Number(m[2]) - 1 }
  m = s.match(/^(1[0-5]|[1-9])([A-O])$/)
  if (m) return { direction: "V", row: ROW_LABELS.indexOf(m[2]), col: Number(m[1]) - 1 }
  return null
}
