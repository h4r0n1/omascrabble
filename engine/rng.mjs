// Seeded pseudo-random generator (sfc32) with a plain, serializable state.
//
// The game keeps its generator state in the saved game, so draws after a
// reload continue exactly where they stopped, and a test can replay a whole
// game from a seed. Functions take the state object and advance it in place;
// the engine clones state before mutating it.

function splitmix32(a) {
  return function() {
    a = (a + 0x9e3779b9) | 0
    let t = a ^ (a >>> 16)
    t = Math.imul(t, 0x21f0aaad)
    t = t ^ (t >>> 15)
    t = Math.imul(t, 0x735a2d97)
    t = t ^ (t >>> 15)
    return t >>> 0
  }
}

export function hashSeed(seed) {
  if (typeof seed === "number" && isFinite(seed)) return seed >>> 0
  const s = String(seed)
  let h = 0x811c9dc5 | 0
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

export function createRng(seed) {
  const next = splitmix32(hashSeed(seed))
  const rng = { seed: hashSeed(seed), s: [next(), next(), next(), next()] }
  for (let i = 0; i < 12; i++) nextUint32(rng)
  return rng
}

export function isRngState(value) {
  return !!value && Array.isArray(value.s) && value.s.length === 4
    && value.s.every(function(v) { return Number.isInteger(v) && v >= 0 && v <= 0xffffffff })
}

export function cloneRng(rng) {
  return { seed: rng.seed, s: rng.s.slice() }
}

export function nextUint32(rng) {
  const s = rng.s
  let a = s[0] | 0, b = s[1] | 0, c = s[2] | 0, d = s[3] | 0
  const t = (((a + b) | 0) + d) | 0
  d = (d + 1) | 0
  a = b ^ (b >>> 9)
  b = (c + (c << 3)) | 0
  c = (c << 21) | (c >>> 11)
  c = (c + t) | 0
  s[0] = a >>> 0; s[1] = b >>> 0; s[2] = c >>> 0; s[3] = d >>> 0
  return t >>> 0
}

// Uniform integer in [0, n), without modulo bias.
export function nextInt(rng, n) {
  if (!(n > 0)) throw new Error("nextInt: n must be positive")
  const limit = Math.floor(0x100000000 / n) * n
  let x
  do { x = nextUint32(rng) } while (x >= limit)
  return x % n
}

export function nextFloat(rng) {
  return nextUint32(rng) / 0x100000000
}

export function shuffleInPlace(rng, array) {
  for (let i = array.length - 1; i > 0; i--) {
    const j = nextInt(rng, i + 1)
    const tmp = array[i]
    array[i] = array[j]
    array[j] = tmp
  }
  return array
}

// A fresh seed for a new game when the caller has none.
export function randomSeed() {
  return (Math.floor(Math.random() * 0x100000000) ^ (Date.now() & 0xffffffff)) >>> 0
}
