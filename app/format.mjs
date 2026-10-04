// French number formatting with a plain no-break space as the thousands
// separator (some monospace fonts lack the narrow one Qt's locale uses).

export function formatInt(value) {
  const n = Math.round(Number(value) || 0)
  const sign = n < 0 ? "−" : ""
  const digits = String(Math.abs(n))
  let out = ""
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += " "
    out += digits.charAt(i)
  }
  return sign + out
}

export function formatDecimal(value, places) {
  const p = places === undefined ? 1 : places
  const n = Number(value) || 0
  const fixed = Math.abs(n).toFixed(p).split(".")
  return (n < 0 ? "−" : "") + formatInt(Number(fixed[0])) + (p > 0 ? "," + fixed[1] : "")
}
